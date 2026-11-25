package store

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

type Session struct {
	ID              uuid.UUID  `json:"id"`
	Mode            string     `json:"mode"`
	StartedAt       time.Time  `json:"startedAt"`
	EndedAt         time.Time  `json:"endedAt"`
	DurationSeconds int32      `json:"durationSeconds"`
	PlannedSeconds  *int32     `json:"plannedSeconds"`
	Subject         *string    `json:"subject"`
	Notes           *string    `json:"notes"`
	LapsSeconds     []int32    `json:"lapsSeconds"`
	SourceDevice    string     `json:"sourceDevice"`
	ClientUpdatedAt time.Time  `json:"clientUpdatedAt"`
	CreatedAt       time.Time  `json:"createdAt"`
	UpdatedAt       time.Time  `json:"updatedAt"`
	DeletedAt       *time.Time `json:"deletedAt"`
	ChangeSeq       int64      `json:"changeSeq"`
}

// SessionInput is a validated write from a client. Times must already be
// truncated to microseconds (PostgreSQL precision) so replays compare equal.
type SessionInput struct {
	ID              uuid.UUID
	Mode            string
	StartedAt       time.Time
	EndedAt         time.Time
	DurationSeconds int32
	PlannedSeconds  *int32
	Subject         *string
	Notes           *string
	LapsSeconds     []int32
	SourceDevice    string
	ClientUpdatedAt time.Time
}

type WriteOutcome int

const (
	Created WriteOutcome = iota + 1
	Updated
	Unchanged // exact replay of the version the server already holds
)

const sessionColumns = `id, mode, started_at, ended_at, duration_seconds, planned_seconds,
	subject, notes, laps_seconds, source_device, client_updated_at, created_at, updated_at,
	deleted_at, change_seq`

func scanSession(row pgx.Row) (Session, error) {
	var s Session
	err := row.Scan(&s.ID, &s.Mode, &s.StartedAt, &s.EndedAt, &s.DurationSeconds, &s.PlannedSeconds,
		&s.Subject, &s.Notes, &s.LapsSeconds, &s.SourceDevice, &s.ClientUpdatedAt, &s.CreatedAt,
		&s.UpdatedAt, &s.DeletedAt, &s.ChangeSeq)
	if s.LapsSeconds == nil {
		s.LapsSeconds = []int32{}
	}
	return s, err
}

// PutSession creates or updates a session using last-writer-wins on the
// client's edit timestamp:
//   - unknown id            -> insert (Created)
//   - same clientUpdatedAt  -> no write (Unchanged), safe for offline retries
//   - newer clientUpdatedAt -> update (Updated)
//   - older, or deleted     -> ErrConflict, returning the server's version
//   - id owned by someone else -> ErrIDTaken, revealing nothing
func (s *Store) PutSession(ctx context.Context, userID uuid.UUID, in SessionInput) (Session, WriteOutcome, error) {
	var (
		out     Session
		outcome WriteOutcome
	)
	if in.LapsSeconds == nil {
		in.LapsSeconds = []int32{}
	}
	err := s.inUserTx(ctx, userID, func(tx pgx.Tx) error {
		var (
			owner           uuid.UUID
			clientUpdatedAt time.Time
			deletedAt       *time.Time
		)
		err := tx.QueryRow(ctx,
			`SELECT user_id, client_updated_at, deleted_at FROM study_sessions WHERE id = $1 FOR UPDATE`,
			in.ID).Scan(&owner, &clientUpdatedAt, &deletedAt)

		switch {
		case errors.Is(err, pgx.ErrNoRows):
			out, err = scanSession(tx.QueryRow(ctx, `
				INSERT INTO study_sessions (id, user_id, mode, started_at, ended_at, duration_seconds,
				       planned_seconds, subject, notes, laps_seconds, source_device, client_updated_at)
				VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
				RETURNING `+sessionColumns,
				in.ID, userID, in.Mode, in.StartedAt, in.EndedAt, in.DurationSeconds, in.PlannedSeconds,
				in.Subject, in.Notes, in.LapsSeconds, in.SourceDevice, in.ClientUpdatedAt))
			outcome = Created
			return err
		case err != nil:
			return err
		case owner != userID:
			return ErrIDTaken
		}

		current, err := scanSession(tx.QueryRow(ctx,
			`SELECT `+sessionColumns+` FROM study_sessions WHERE id = $1`, in.ID))
		if err != nil {
			return err
		}
		switch {
		case deletedAt != nil || in.ClientUpdatedAt.Before(clientUpdatedAt):
			out = current
			return ErrConflict
		case in.ClientUpdatedAt.Equal(clientUpdatedAt):
			out, outcome = current, Unchanged
			return nil
		}

		out, err = scanSession(tx.QueryRow(ctx, `
			UPDATE study_sessions
			   SET mode = $3, started_at = $4, ended_at = $5, duration_seconds = $6,
			       planned_seconds = $7, subject = $8, notes = $9, laps_seconds = $10,
			       source_device = $11, client_updated_at = $12
			 WHERE id = $1 AND user_id = $2
			RETURNING `+sessionColumns,
			in.ID, userID, in.Mode, in.StartedAt, in.EndedAt, in.DurationSeconds, in.PlannedSeconds,
			in.Subject, in.Notes, in.LapsSeconds, in.SourceDevice, in.ClientUpdatedAt))
		outcome = Updated
		return err
	})
	if errors.Is(err, ErrConflict) {
		return out, 0, ErrConflict
	}
	if err != nil {
		return Session{}, 0, err
	}
	return out, outcome, nil
}

func (s *Store) GetSession(ctx context.Context, userID, id uuid.UUID) (Session, error) {
	out, err := scanSession(s.pool.QueryRow(ctx,
		`SELECT `+sessionColumns+` FROM study_sessions WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL`,
		id, userID))
	if errors.Is(err, pgx.ErrNoRows) {
		return Session{}, ErrNotFound
	}
	return out, err
}

// DeleteSession soft-deletes so other devices receive a tombstone through the
// change feed. Deleting an already-deleted session succeeds (idempotent).
func (s *Store) DeleteSession(ctx context.Context, userID, id uuid.UUID) error {
	return s.inUserTx(ctx, userID, func(tx pgx.Tx) error {
		var deletedAt *time.Time
		err := tx.QueryRow(ctx,
			`SELECT deleted_at FROM study_sessions WHERE id = $1 AND user_id = $2 FOR UPDATE`,
			id, userID).Scan(&deletedAt)
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrNotFound
		}
		if err != nil || deletedAt != nil {
			return err
		}
		_, err = tx.Exec(ctx,
			`UPDATE study_sessions SET deleted_at = now() WHERE id = $1 AND user_id = $2`, id, userID)
		return err
	})
}

// ListSessions returns live sessions that started in [from, to), newest first.
func (s *Store) ListSessions(ctx context.Context, userID uuid.UUID, from, to time.Time, limit int) ([]Session, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT `+sessionColumns+`
		  FROM study_sessions
		 WHERE user_id = $1 AND deleted_at IS NULL AND started_at >= $2 AND started_at < $3
		 ORDER BY started_at DESC, id
		 LIMIT $4`, userID, from, to, limit)
	if err != nil {
		return nil, err
	}
	return collectSessions(rows)
}

// SessionChanges returns every row (tombstones included) changed after the
// cursor, oldest change first. hasMore reports whether another page exists.
func (s *Store) SessionChanges(ctx context.Context, userID uuid.UUID, since int64, limit int) (changes []Session, hasMore bool, err error) {
	rows, err := s.pool.Query(ctx, `
		SELECT `+sessionColumns+`
		  FROM study_sessions
		 WHERE user_id = $1 AND change_seq > $2
		 ORDER BY change_seq
		 LIMIT $3`, userID, since, limit+1)
	if err != nil {
		return nil, false, err
	}
	changes, err = collectSessions(rows)
	if err != nil {
		return nil, false, err
	}
	if len(changes) > limit {
		return changes[:limit], true, nil
	}
	return changes, false, nil
}

func collectSessions(rows pgx.Rows) ([]Session, error) {
	defer rows.Close()
	out := []Session{}
	for rows.Next() {
		s, err := scanSession(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, s)
	}
	return out, rows.Err()
}
