package httpapi

import (
	"fmt"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"

	"github.com/eagle-engineering/ecosystem/api/internal/store"
)

// Clock skew we tolerate between a device and the server.
const maxClockSkew = 5 * time.Minute

type sessionBody struct {
	Mode            string     `json:"mode"`
	StartedAt       *time.Time `json:"startedAt"`
	EndedAt         *time.Time `json:"endedAt"`
	DurationSeconds int64      `json:"durationSeconds"`
	PlannedSeconds  *int64     `json:"plannedSeconds"`
	Subject         *string    `json:"subject"`
	Notes           *string    `json:"notes"`
	LapsSeconds     []int64    `json:"lapsSeconds"`
	SourceDevice    string     `json:"sourceDevice"`
	ClientUpdatedAt *time.Time `json:"clientUpdatedAt"`
}

var validModes = map[string]bool{"stopwatch": true, "countdown": true, "pomodoro": true}

func (b sessionBody) validate(id uuid.UUID, now time.Time) (store.SessionInput, []FieldError) {
	var errs []FieldError
	add := func(field, format string, args ...any) {
		errs = append(errs, FieldError{Field: field, Message: fmt.Sprintf(format, args...)})
	}
	latest := now.Add(maxClockSkew)

	if !validModes[b.Mode] {
		add("mode", "must be one of stopwatch, countdown, pomodoro")
	}
	if b.StartedAt == nil {
		add("startedAt", "is required (RFC 3339)")
	} else if b.StartedAt.After(latest) {
		add("startedAt", "is in the future")
	}
	if b.EndedAt == nil {
		add("endedAt", "is required (RFC 3339)")
	} else if b.EndedAt.After(latest) {
		add("endedAt", "is in the future")
	}
	if b.StartedAt != nil && b.EndedAt != nil {
		span := b.EndedAt.Sub(*b.StartedAt)
		if span < 0 {
			add("endedAt", "must not be before startedAt")
		} else if time.Duration(b.DurationSeconds)*time.Second > span+time.Second {
			add("durationSeconds", "exceeds the wall-clock time between startedAt and endedAt")
		}
	}
	if b.DurationSeconds < 1 || b.DurationSeconds > 86400 {
		add("durationSeconds", "must be between 1 and 86400")
	}
	if b.PlannedSeconds != nil && (*b.PlannedSeconds < 1 || *b.PlannedSeconds > 86400) {
		add("plannedSeconds", "must be between 1 and 86400")
	}
	subject := trimmedOrNil(b.Subject)
	if subject != nil && utf8.RuneCountInString(*subject) > 120 {
		add("subject", "must be at most 120 characters")
	}
	notes := trimmedOrNil(b.Notes)
	if notes != nil && utf8.RuneCountInString(*notes) > 4000 {
		add("notes", "must be at most 4000 characters")
	}
	if len(b.LapsSeconds) > 500 {
		add("lapsSeconds", "must contain at most 500 laps")
	}
	laps := make([]int32, 0, len(b.LapsSeconds))
	var previous int64
	for i, lap := range b.LapsSeconds {
		if lap < previous || lap > b.DurationSeconds {
			add(fmt.Sprintf("lapsSeconds[%d]", i), "laps must be cumulative, non-decreasing and within durationSeconds")
			break
		}
		previous = lap
		laps = append(laps, int32(lap))
	}
	device := strings.TrimSpace(b.SourceDevice)
	if device == "" || utf8.RuneCountInString(device) > 120 {
		add("sourceDevice", "is required and must be at most 120 characters")
	}
	if b.ClientUpdatedAt == nil {
		add("clientUpdatedAt", "is required (RFC 3339)")
	} else if b.ClientUpdatedAt.After(latest) {
		add("clientUpdatedAt", "is in the future")
	}
	if len(errs) > 0 {
		return store.SessionInput{}, errs
	}

	in := store.SessionInput{
		ID:              id,
		Mode:            b.Mode,
		StartedAt:       micros(*b.StartedAt),
		EndedAt:         micros(*b.EndedAt),
		DurationSeconds: int32(b.DurationSeconds),
		Subject:         subject,
		Notes:           notes,
		LapsSeconds:     laps,
		SourceDevice:    device,
		ClientUpdatedAt: micros(*b.ClientUpdatedAt),
	}
	if b.PlannedSeconds != nil {
		p := int32(*b.PlannedSeconds)
		in.PlannedSeconds = &p
	}
	return in, nil
}

type preferencesBody struct {
	Timezone            string `json:"timezone"`
	DailyTargetMinutes  *int   `json:"dailyTargetMinutes"`
	WeeklyTargetMinutes *int   `json:"weeklyTargetMinutes"`
}

func (b preferencesBody) validate() (store.Preferences, []FieldError) {
	var errs []FieldError
	if b.Timezone == "" || b.Timezone == "Local" {
		errs = append(errs, FieldError{"timezone", "must be an IANA zone such as Asia/Kolkata"})
	} else if _, err := time.LoadLocation(b.Timezone); err != nil {
		errs = append(errs, FieldError{"timezone", "is not a known IANA zone"})
	}
	if b.DailyTargetMinutes == nil || *b.DailyTargetMinutes < 0 || *b.DailyTargetMinutes > 1440 {
		errs = append(errs, FieldError{"dailyTargetMinutes", "is required and must be between 0 and 1440"})
	}
	if b.WeeklyTargetMinutes == nil || *b.WeeklyTargetMinutes < 0 || *b.WeeklyTargetMinutes > 10080 {
		errs = append(errs, FieldError{"weeklyTargetMinutes", "is required and must be between 0 and 10080"})
	}
	if len(errs) > 0 {
		return store.Preferences{}, errs
	}
	return store.Preferences{
		Timezone:            b.Timezone,
		DailyTargetMinutes:  *b.DailyTargetMinutes,
		WeeklyTargetMinutes: *b.WeeklyTargetMinutes,
	}, nil
}

func trimmedOrNil(s *string) *string {
	if s == nil {
		return nil
	}
	t := strings.TrimSpace(*s)
	if t == "" {
		return nil
	}
	return &t
}

// micros truncates to PostgreSQL's timestamptz precision so that a replayed
// clientUpdatedAt compares equal to the stored value.
func micros(t time.Time) time.Time { return t.UTC().Truncate(time.Microsecond) }
