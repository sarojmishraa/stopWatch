// Package store is the PostgreSQL data layer. Every query that touches user
// data is scoped by the caller's user ID; there is no unscoped accessor.
package store

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/golang-migrate/migrate/v4"
	_ "github.com/golang-migrate/migrate/v4/database/pgx/v5" // registers pgx5://
	"github.com/golang-migrate/migrate/v4/source/iofs"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/eagle-engineering/ecosystem/api/migrations"
)

var (
	ErrNotFound = errors.New("not found")
	// ErrConflict means the server holds a newer (or deleted) version.
	ErrConflict = errors.New("conflict")
	// ErrIDTaken means the client-generated ID belongs to another user.
	ErrIDTaken = errors.New("id already in use")
)

type Store struct {
	pool *pgxpool.Pool
	now  func() time.Time
}

func Open(ctx context.Context, databaseURL string) (*Store, error) {
	cfg, err := pgxpool.ParseConfig(databaseURL)
	if err != nil {
		return nil, fmt.Errorf("parse DATABASE_URL: %w", err)
	}
	cfg.MaxConns = 20
	cfg.MaxConnIdleTime = 5 * time.Minute
	cfg.ConnConfig.RuntimeParams["timezone"] = "UTC"
	cfg.ConnConfig.RuntimeParams["application_name"] = "eagle-api"

	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		return nil, fmt.Errorf("open pool: %w", err)
	}
	pingCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	if err := pool.Ping(pingCtx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("ping database: %w", err)
	}
	return &Store{pool: pool, now: time.Now}, nil
}

// SetClock overrides the clock used for date-relative queries (tests only).
func (s *Store) SetClock(now func() time.Time) { s.now = now }

func (s *Store) Close() { s.pool.Close() }

func (s *Store) Ping(ctx context.Context) error { return s.pool.Ping(ctx) }

// Pool exposes the pool to tests that need to inspect raw rows.
func (s *Store) Pool() *pgxpool.Pool { return s.pool }

// Migrate applies all pending migrations from the embedded SQL files.
func Migrate(databaseURL string) error {
	src, err := iofs.New(migrations.FS, ".")
	if err != nil {
		return err
	}
	m, err := migrate.NewWithSourceInstance("iofs", src, toMigrateURL(databaseURL))
	if err != nil {
		return fmt.Errorf("init migrations: %w", err)
	}
	defer m.Close()
	if err := m.Up(); err != nil && !errors.Is(err, migrate.ErrNoChange) {
		return fmt.Errorf("apply migrations: %w", err)
	}
	return nil
}

func toMigrateURL(u string) string {
	for _, prefix := range []string{"postgresql://", "postgres://"} {
		if strings.HasPrefix(u, prefix) {
			return "pgx5://" + strings.TrimPrefix(u, prefix)
		}
	}
	return u
}

// inUserTx runs fn in a transaction that holds a row lock on the user. All
// writes to synced tables go through here so that, per user, change_seq values
// are assigned and committed in the same order, which keeps pull cursors
// gap-free.
func (s *Store) inUserTx(ctx context.Context, userID [16]byte, fn func(pgx.Tx) error) error {
	return pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		var one int
		err := tx.QueryRow(ctx, `SELECT 1 FROM users WHERE id = $1 FOR UPDATE`, userID).Scan(&one)
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrNotFound
		}
		if err != nil {
			return err
		}
		return fn(tx)
	})
}
