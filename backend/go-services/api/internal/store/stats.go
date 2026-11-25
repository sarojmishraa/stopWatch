package store

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

type DayTotal struct {
	Date    string `json:"date"` // YYYY-MM-DD in the user's timezone
	Seconds int64  `json:"seconds"`
}

type Summary struct {
	Timezone            string     `json:"timezone"`
	AsOf                time.Time  `json:"asOf"`
	TodaySeconds        int64      `json:"todaySeconds"`
	WeekSeconds         int64      `json:"weekSeconds"`
	MonthSeconds        int64      `json:"monthSeconds"`
	TotalSeconds        int64      `json:"totalSeconds"`
	TodaySessions       int64      `json:"todaySessions"`
	TotalSessions       int64      `json:"totalSessions"`
	DailyTargetMinutes  int        `json:"dailyTargetMinutes"`
	WeeklyTargetMinutes int        `json:"weeklyTargetMinutes"`
	LastSevenDays       []DayTotal `json:"lastSevenDays"`
}

// Summary aggregates persisted sessions in the user's own timezone. Day, ISO
// week (Monday start) and month boundaries are computed by PostgreSQL from the
// IANA zone, so DST zones are handled correctly too. A session counts toward
// the local day on which it started.
func (s *Store) Summary(ctx context.Context, userID uuid.UUID) (Summary, error) {
	now := s.now().UTC()
	out := Summary{AsOf: now}
	err := s.pool.QueryRow(ctx, `
		WITH b AS (
			SELECT p.timezone, p.daily_target_minutes, p.weekly_target_minutes,
			       date_trunc('day',   $2::timestamptz AT TIME ZONE p.timezone) AT TIME ZONE p.timezone AS day_start,
			       date_trunc('week',  $2::timestamptz AT TIME ZONE p.timezone) AT TIME ZONE p.timezone AS week_start,
			       date_trunc('month', $2::timestamptz AT TIME ZONE p.timezone) AT TIME ZONE p.timezone AS month_start
			  FROM user_preferences p
			 WHERE p.user_id = $1
		)
		SELECT b.timezone, b.daily_target_minutes, b.weekly_target_minutes,
		       COALESCE(SUM(s.duration_seconds) FILTER (WHERE s.started_at >= b.day_start), 0),
		       COALESCE(SUM(s.duration_seconds) FILTER (WHERE s.started_at >= b.week_start), 0),
		       COALESCE(SUM(s.duration_seconds) FILTER (WHERE s.started_at >= b.month_start), 0),
		       COALESCE(SUM(s.duration_seconds), 0),
		       COUNT(s.id) FILTER (WHERE s.started_at >= b.day_start),
		       COUNT(s.id)
		  FROM b
		  LEFT JOIN study_sessions s
		         ON s.user_id = $1 AND s.deleted_at IS NULL AND s.started_at <= $2
		 GROUP BY b.timezone, b.daily_target_minutes, b.weekly_target_minutes`,
		userID, now,
	).Scan(&out.Timezone, &out.DailyTargetMinutes, &out.WeeklyTargetMinutes,
		&out.TodaySeconds, &out.WeekSeconds, &out.MonthSeconds, &out.TotalSeconds,
		&out.TodaySessions, &out.TotalSessions)
	if errors.Is(err, pgx.ErrNoRows) {
		return Summary{}, ErrNotFound
	}
	if err != nil {
		return Summary{}, err
	}

	rows, err := s.pool.Query(ctx, `
		WITH p AS (SELECT timezone FROM user_preferences WHERE user_id = $1),
		     days AS (
			SELECT d AS local_day, p.timezone
			  FROM p, generate_series(
			           date_trunc('day', $2::timestamptz AT TIME ZONE p.timezone) - interval '6 days',
			           date_trunc('day', $2::timestamptz AT TIME ZONE p.timezone),
			           interval '1 day') AS d
		)
		SELECT to_char(days.local_day, 'YYYY-MM-DD'), COALESCE(SUM(s.duration_seconds), 0)
		  FROM days
		  LEFT JOIN study_sessions s
		         ON s.user_id = $1 AND s.deleted_at IS NULL
		        AND s.started_at >= days.local_day AT TIME ZONE days.timezone
		        AND s.started_at <  (days.local_day + interval '1 day') AT TIME ZONE days.timezone
		 GROUP BY days.local_day
		 ORDER BY days.local_day`, userID, now)
	if err != nil {
		return Summary{}, err
	}
	out.LastSevenDays, err = pgx.CollectRows(rows, func(r pgx.CollectableRow) (DayTotal, error) {
		var d DayTotal
		return d, r.Scan(&d.Date, &d.Seconds)
	})
	return out, err
}
