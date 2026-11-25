package store

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

type User struct {
	ID          uuid.UUID   `json:"id"`
	Email       string      `json:"email"`
	DisplayName *string     `json:"displayName"`
	CreatedAt   time.Time   `json:"createdAt"`
	Preferences Preferences `json:"preferences"`
}

type Preferences struct {
	Timezone            string    `json:"timezone"`
	DailyTargetMinutes  int       `json:"dailyTargetMinutes"`
	WeeklyTargetMinutes int       `json:"weeklyTargetMinutes"`
	UpdatedAt           time.Time `json:"updatedAt"`
}

// EnsureUser creates the user (with default preferences) on first sight and
// refreshes the profile fields from the identity provider afterwards.
func (s *Store) EnsureUser(ctx context.Context, id uuid.UUID, email, name string) (User, error) {
	var displayName *string
	if name != "" {
		displayName = &name
	}
	var u User
	err := pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		err := tx.QueryRow(ctx, `
			INSERT INTO users (id, email, display_name)
			VALUES ($1, $2, $3)
			ON CONFLICT (id) DO UPDATE
			   SET email        = EXCLUDED.email,
			       display_name = COALESCE(EXCLUDED.display_name, users.display_name),
			       updated_at   = CASE WHEN users.email IS DISTINCT FROM EXCLUDED.email
			                            OR users.display_name IS DISTINCT FROM COALESCE(EXCLUDED.display_name, users.display_name)
			                           THEN now() ELSE users.updated_at END,
			       last_seen_at = now()
			RETURNING id, email, display_name, created_at`,
			id, email, displayName,
		).Scan(&u.ID, &u.Email, &u.DisplayName, &u.CreatedAt)
		if err != nil {
			return err
		}
		_, err = tx.Exec(ctx,
			`INSERT INTO user_preferences (user_id) VALUES ($1) ON CONFLICT (user_id) DO NOTHING`, id)
		return err
	})
	if err != nil {
		return User{}, err
	}
	u.Preferences, err = s.GetPreferences(ctx, id)
	return u, err
}

func (s *Store) GetPreferences(ctx context.Context, userID uuid.UUID) (Preferences, error) {
	var p Preferences
	err := s.pool.QueryRow(ctx, `
		SELECT timezone, daily_target_minutes, weekly_target_minutes, updated_at
		  FROM user_preferences WHERE user_id = $1`, userID,
	).Scan(&p.Timezone, &p.DailyTargetMinutes, &p.WeeklyTargetMinutes, &p.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return Preferences{}, ErrNotFound
	}
	return p, err
}

func (s *Store) UpdatePreferences(ctx context.Context, userID uuid.UUID, p Preferences) (Preferences, error) {
	var out Preferences
	err := s.pool.QueryRow(ctx, `
		UPDATE user_preferences
		   SET timezone = $2, daily_target_minutes = $3, weekly_target_minutes = $4, updated_at = now()
		 WHERE user_id = $1
		RETURNING timezone, daily_target_minutes, weekly_target_minutes, updated_at`,
		userID, p.Timezone, p.DailyTargetMinutes, p.WeeklyTargetMinutes,
	).Scan(&out.Timezone, &out.DailyTargetMinutes, &out.WeeklyTargetMinutes, &out.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return Preferences{}, ErrNotFound
	}
	return out, err
}
