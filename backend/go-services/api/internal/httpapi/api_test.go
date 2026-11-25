package httpapi_test

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"

	"github.com/eagle-engineering/ecosystem/api/internal/auth"
	"github.com/eagle-engineering/ecosystem/api/internal/httpapi"
	"github.com/eagle-engineering/ecosystem/api/internal/store"
	"github.com/eagle-engineering/ecosystem/api/internal/testutil"
)

// 2026-12-01 10:00 in Asia/Kolkata (a Tuesday; the plan starts Monday 30 Nov).
var fixedNow = time.Date(2026, 12, 1, 4, 30, 0, 0, time.UTC)

type env struct {
	t      *testing.T
	srv    *httptest.Server
	store  *store.Store
	issuer *testutil.Issuer
}

func newEnv(t *testing.T) *env {
	t.Helper()
	st := testutil.NewStore(t)
	st.SetClock(func() time.Time { return fixedNow })
	iss := testutil.NewIssuer(t)
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	v, err := auth.NewJWKSVerifier(ctx, iss.JWKSURL(), iss.Origin, iss.Origin)
	if err != nil {
		t.Fatal(err)
	}
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	h := httpapi.New(st, v, log, httpapi.Options{
		CORSOrigins: []string{"http://localhost:3000"},
		Now:         func() time.Time { return fixedNow },
	})
	srv := httptest.NewServer(h)
	t.Cleanup(srv.Close)
	return &env{t: t, srv: srv, store: st, issuer: iss}
}

type user struct {
	id    uuid.UUID
	token string
}

func (e *env) newUser(email string) user {
	id := uuid.New()
	return user{id: id, token: e.issuer.Token(e.t, id, email)}
}

func (e *env) do(method, path, token string, body any) (int, map[string]any, http.Header) {
	e.t.Helper()
	var r io.Reader
	switch b := body.(type) {
	case nil:
	case string:
		r = bytes.NewBufferString(b)
	default:
		raw, _ := json.Marshal(b)
		r = bytes.NewReader(raw)
	}
	req, _ := http.NewRequest(method, e.srv.URL+path, r)
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		e.t.Fatal(err)
	}
	defer res.Body.Close()
	raw, _ := io.ReadAll(res.Body)
	var out map[string]any
	if len(raw) > 0 {
		if err := json.Unmarshal(raw, &out); err != nil {
			e.t.Fatalf("%s %s: non-JSON response %d: %s", method, path, res.StatusCode, raw)
		}
	}
	return res.StatusCode, out, res.Header
}

func session(start time.Time, seconds int, editedAt time.Time) map[string]any {
	return map[string]any{
		"mode":            "stopwatch",
		"startedAt":       start.Format(time.RFC3339Nano),
		"endedAt":         start.Add(time.Duration(seconds) * time.Second).Format(time.RFC3339Nano),
		"durationSeconds": seconds,
		"subject":         "Java concurrency",
		"lapsSeconds":     []int{},
		"sourceDevice":    "pixel-8",
		"clientUpdatedAt": editedAt.Format(time.RFC3339Nano),
	}
}

func expectStatus(t *testing.T, got, want int, body map[string]any) {
	t.Helper()
	if got != want {
		t.Fatalf("status = %d, want %d; body = %v", got, want, body)
	}
}

func TestHealthIsPublicAndAPIRequiresAuth(t *testing.T) {
	e := newEnv(t)
	status, body, _ := e.do("GET", "/healthz", "", nil)
	expectStatus(t, status, 200, body)
	status, body, _ = e.do("GET", "/readyz", "", nil)
	expectStatus(t, status, 200, body)

	status, body, hdr := e.do("GET", "/v1/me", "", nil)
	expectStatus(t, status, 401, body)
	if hdr.Get("WWW-Authenticate") == "" || hdr.Get("Content-Type") != "application/problem+json" {
		t.Fatalf("missing WWW-Authenticate or problem+json content type: %v", hdr)
	}
}

func TestRejectsInvalidTokens(t *testing.T) {
	e := newEnv(t)
	id := uuid.New()
	hs256, _ := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"sub": id.String(), "email": "a@b.c", "iss": e.issuer.Origin, "aud": e.issuer.Origin,
		"exp": time.Now().Add(time.Hour).Unix(),
	}).SignedString([]byte("guessable-secret"))

	cases := map[string]struct {
		token string
		want  int
	}{
		"signed by unknown key":     {e.issuer.ForeignToken(t, id, "a@b.c"), 401},
		"expired":                   {e.issuer.Token(t, id, "a@b.c", testutil.WithClaim("exp", time.Now().Add(-time.Hour).Unix())), 401},
		"wrong issuer":              {e.issuer.Token(t, id, "a@b.c", testutil.WithClaim("iss", "https://evil.example")), 401},
		"wrong audience":            {e.issuer.Token(t, id, "a@b.c", testutil.WithClaim("aud", "https://other.example")), 401},
		"no expiry":                 {e.issuer.Token(t, id, "a@b.c", testutil.WithClaim("exp", nil)), 401},
		"subject not a uuid":        {e.issuer.Token(t, id, "a@b.c", testutil.WithClaim("sub", "admin")), 401},
		"missing email":             {e.issuer.Token(t, id, "", testutil.WithClaim("email", "")), 401},
		"HS256 algorithm confusion": {hs256, 401},
		"garbage":                   {"not.a.jwt", 401},
		"banned account":            {e.issuer.Token(t, id, "a@b.c", testutil.WithClaim("banned", true)), 403},
	}
	for name, tc := range cases {
		t.Run(name, func(t *testing.T) {
			status, body, _ := e.do("GET", "/v1/me", tc.token, nil)
			expectStatus(t, status, tc.want, body)
		})
	}
}

func TestMeProvisionsUserWithKolkataDefaults(t *testing.T) {
	e := newEnv(t)
	u := e.newUser("learner@example.com")
	status, body, _ := e.do("GET", "/v1/me", u.token, nil)
	expectStatus(t, status, 200, body)
	if body["id"] != u.id.String() || body["email"] != "learner@example.com" {
		t.Fatalf("unexpected profile: %v", body)
	}
	prefs := body["preferences"].(map[string]any)
	if prefs["timezone"] != "Asia/Kolkata" || prefs["weeklyTargetMinutes"] != float64(3000) {
		t.Fatalf("unexpected default preferences: %v", prefs)
	}
}

func TestPreferences(t *testing.T) {
	e := newEnv(t)
	u := e.newUser("p@example.com")

	status, body, _ := e.do("PUT", "/v1/me/preferences", u.token,
		map[string]any{"timezone": "Mars/Olympus", "dailyTargetMinutes": 2000, "weeklyTargetMinutes": 3000})
	expectStatus(t, status, 422, body)
	if errs := body["errors"].([]any); len(errs) != 2 {
		t.Fatalf("want timezone and dailyTargetMinutes errors, got %v", errs)
	}

	status, body, _ = e.do("PUT", "/v1/me/preferences", u.token,
		map[string]any{"timezone": "Europe/Berlin", "dailyTargetMinutes": 300, "weeklyTargetMinutes": 2400})
	expectStatus(t, status, 200, body)
	if body["timezone"] != "Europe/Berlin" {
		t.Fatalf("preferences not saved: %v", body)
	}
}

func TestPutSessionIsIdempotentAndLastWriterWins(t *testing.T) {
	e := newEnv(t)
	u := e.newUser("lww@example.com")
	id := uuid.New()
	path := "/v1/study-sessions/" + id.String()
	start := fixedNow.Add(-2 * time.Hour)
	edit1 := fixedNow.Add(-time.Hour).Add(123456789 * time.Nanosecond) // sub-microsecond precision on purpose

	status, created, hdr := e.do("PUT", path, u.token, session(start, 1500, edit1))
	expectStatus(t, status, 201, created)
	if hdr.Get("Location") != path {
		t.Fatalf("Location = %q", hdr.Get("Location"))
	}

	// Offline retry of the same write: no duplicate, no new change.
	status, replay, _ := e.do("PUT", path, u.token, session(start, 1500, edit1))
	expectStatus(t, status, 200, replay)
	if replay["changeSeq"] != created["changeSeq"] {
		t.Fatalf("replay changed changeSeq: %v -> %v", created["changeSeq"], replay["changeSeq"])
	}

	// A stale edit from another device loses and receives the server copy.
	status, conflict, _ := e.do("PUT", path, u.token, session(start, 900, edit1.Add(-time.Minute)))
	expectStatus(t, status, 409, conflict)
	if cur := conflict["current"].(map[string]any); cur["durationSeconds"] != float64(1500) {
		t.Fatalf("conflict should carry the server version, got %v", cur)
	}

	// A newer edit wins.
	status, updated, _ := e.do("PUT", path, u.token, session(start, 1800, edit1.Add(time.Minute)))
	expectStatus(t, status, 200, updated)
	if updated["durationSeconds"] != float64(1800) || updated["changeSeq"].(float64) <= created["changeSeq"].(float64) {
		t.Fatalf("update not applied or changeSeq not advanced: %v", updated)
	}

	var rows, audits int
	pool := e.store.Pool()
	_ = pool.QueryRow(context.Background(), `SELECT count(*) FROM study_sessions WHERE id = $1`, id).Scan(&rows)
	_ = pool.QueryRow(context.Background(), `SELECT count(*) FROM study_session_audit WHERE session_id = $1`, id).Scan(&audits)
	if rows != 1 || audits != 2 {
		t.Fatalf("rows = %d (want 1), audit entries = %d (want INSERT+UPDATE = 2)", rows, audits)
	}
}

func TestSessionValidation(t *testing.T) {
	e := newEnv(t)
	u := e.newUser("v@example.com")
	start := fixedNow.Add(-time.Hour)
	mutate := func(f func(map[string]any)) map[string]any {
		b := session(start, 600, fixedNow)
		f(b)
		return b
	}
	cases := map[string]struct {
		body  any
		want  int
		field string
	}{
		"unknown mode":            {mutate(func(b map[string]any) { b["mode"] = "nap" }), 422, "mode"},
		"ends before it starts":   {mutate(func(b map[string]any) { b["endedAt"] = start.Add(-time.Minute).Format(time.RFC3339) }), 422, "endedAt"},
		"more focus than elapsed": {mutate(func(b map[string]any) { b["durationSeconds"] = 3600 }), 422, "durationSeconds"},
		"zero duration":           {mutate(func(b map[string]any) { b["durationSeconds"] = 0 }), 422, "durationSeconds"},
		"in the future":           {mutate(func(b map[string]any) { b["startedAt"] = fixedNow.Add(time.Hour).Format(time.RFC3339) }), 422, "startedAt"},
		"laps out of order":       {mutate(func(b map[string]any) { b["lapsSeconds"] = []int{300, 100} }), 422, "lapsSeconds[1]"},
		"missing device":          {mutate(func(b map[string]any) { b["sourceDevice"] = "  " }), 422, "sourceDevice"},
		"missing edit timestamp":  {mutate(func(b map[string]any) { delete(b, "clientUpdatedAt") }), 422, "clientUpdatedAt"},
		"unknown field":           {mutate(func(b map[string]any) { b["durationSecs"] = 1 }), 400, ""},
		"two JSON objects":        {`{"mode":"stopwatch"}{"mode":"stopwatch"}`, 400, ""},
	}
	for name, tc := range cases {
		t.Run(name, func(t *testing.T) {
			status, body, _ := e.do("PUT", "/v1/study-sessions/"+uuid.NewString(), u.token, tc.body)
			expectStatus(t, status, tc.want, body)
			if tc.field != "" {
				found := false
				for _, fe := range body["errors"].([]any) {
					found = found || fe.(map[string]any)["field"] == tc.field
				}
				if !found {
					t.Fatalf("expected an error for %q, got %v", tc.field, body["errors"])
				}
			}
		})
	}

	status, body, _ := e.do("PUT", "/v1/study-sessions/not-a-uuid", u.token, session(start, 600, fixedNow))
	expectStatus(t, status, 400, body)
}

func TestUsersCannotSeeOrTouchEachOthersSessions(t *testing.T) {
	e := newEnv(t)
	alice, bob := e.newUser("alice@example.com"), e.newUser("bob@example.com")
	id := uuid.NewString()
	path := "/v1/study-sessions/" + id
	status, body, _ := e.do("PUT", path, alice.token, session(fixedNow.Add(-time.Hour), 600, fixedNow))
	expectStatus(t, status, 201, body)

	status, body, _ = e.do("GET", path, bob.token, nil)
	expectStatus(t, status, 404, body)
	status, body, _ = e.do("DELETE", path, bob.token, nil)
	expectStatus(t, status, 404, body)
	status, body, _ = e.do("PUT", path, bob.token, session(fixedNow.Add(-time.Hour), 60, fixedNow.Add(time.Minute)))
	expectStatus(t, status, 409, body)
	if body["current"] != nil {
		t.Fatalf("must not leak another user's session: %v", body)
	}
	_, list, _ := e.do("GET", "/v1/study-sessions", bob.token, nil)
	_, changes, _ := e.do("GET", "/v1/sync/study-sessions", bob.token, nil)
	if len(list["sessions"].([]any)) != 0 || len(changes["changes"].([]any)) != 0 {
		t.Fatalf("bob sees alice's data: list=%v changes=%v", list, changes)
	}

	status, body, _ = e.do("GET", path, alice.token, nil)
	expectStatus(t, status, 200, body)
	if body["durationSeconds"] != float64(600) {
		t.Fatalf("alice's session was modified by bob: %v", body)
	}
}

func TestDeleteLeavesSyncTombstone(t *testing.T) {
	e := newEnv(t)
	u := e.newUser("d@example.com")
	path := "/v1/study-sessions/" + uuid.NewString()
	e.do("PUT", path, u.token, session(fixedNow.Add(-time.Hour), 600, fixedNow))

	status, body, _ := e.do("DELETE", path, u.token, nil)
	expectStatus(t, status, 204, body)
	status, body, _ = e.do("DELETE", path, u.token, nil)
	expectStatus(t, status, 204, body) // idempotent
	status, body, _ = e.do("GET", path, u.token, nil)
	expectStatus(t, status, 404, body)

	_, list, _ := e.do("GET", "/v1/study-sessions", u.token, nil)
	if len(list["sessions"].([]any)) != 0 {
		t.Fatalf("deleted session still listed: %v", list)
	}
	_, feed, _ := e.do("GET", "/v1/sync/study-sessions", u.token, nil)
	changes := feed["changes"].([]any)
	if len(changes) != 1 || changes[0].(map[string]any)["deletedAt"] == nil {
		t.Fatalf("expected one tombstone in the change feed, got %v", changes)
	}

	// A device that never saw the delete cannot resurrect the session.
	status, body, _ = e.do("PUT", path, u.token, session(fixedNow.Add(-time.Hour), 600, fixedNow.Add(time.Minute)))
	expectStatus(t, status, 409, body)
}

func TestSyncFeedPaginatesWithoutGaps(t *testing.T) {
	e := newEnv(t)
	u := e.newUser("sync@example.com")
	for i := range 5 {
		e.do("PUT", "/v1/study-sessions/"+uuid.NewString(), u.token,
			session(fixedNow.Add(-time.Duration(i+1)*time.Hour), 600, fixedNow))
	}
	seen := map[string]bool{}
	cursor, pages := 0.0, 0
	for {
		_, page, _ := e.do("GET", fmt.Sprintf("/v1/sync/study-sessions?since=%d&limit=2", int64(cursor)), u.token, nil)
		pages++
		for _, c := range page["changes"].([]any) {
			seq := c.(map[string]any)["changeSeq"].(float64)
			if seq <= cursor {
				t.Fatalf("changeSeq %v not after cursor %v", seq, cursor)
			}
			seen[c.(map[string]any)["id"].(string)] = true
		}
		cursor = page["nextCursor"].(float64)
		if !page["hasMore"].(bool) {
			break
		}
	}
	if len(seen) != 5 || pages != 3 {
		t.Fatalf("saw %d sessions over %d pages, want 5 over 3", len(seen), pages)
	}
	status, body, _ := e.do("GET", "/v1/sync/study-sessions?limit=0", u.token, nil)
	expectStatus(t, status, 422, body)
}

func TestSummaryUsesUserTimezoneBoundaries(t *testing.T) {
	e := newEnv(t)
	u := e.newUser("tz@example.com")
	put := func(startUTC time.Time, seconds int) {
		status, body, _ := e.do("PUT", "/v1/study-sessions/"+uuid.NewString(), u.token, session(startUTC, seconds, fixedNow))
		expectStatus(t, status, 201, body)
	}
	put(time.Date(2026, 11, 30, 18, 45, 0, 0, time.UTC), 1800) // 00:15 IST Tue 1 Dec  -> today
	put(time.Date(2026, 11, 30, 18, 15, 0, 0, time.UTC), 600)  // 23:45 IST Mon 30 Nov -> this week, last month
	put(time.Date(2026, 11, 29, 10, 0, 0, 0, time.UTC), 300)   // Sun 29 Nov           -> previous week

	status, s, _ := e.do("GET", "/v1/stats/summary", u.token, nil)
	expectStatus(t, status, 200, s)
	want := map[string]float64{"todaySeconds": 1800, "weekSeconds": 2400, "monthSeconds": 1800,
		"totalSeconds": 2700, "todaySessions": 1, "totalSessions": 3}
	for k, v := range want {
		if s[k] != v {
			t.Errorf("%s = %v, want %v", k, s[k], v)
		}
	}
	days := s["lastSevenDays"].([]any)
	if len(days) != 7 {
		t.Fatalf("lastSevenDays has %d entries", len(days))
	}
	last := days[6].(map[string]any)
	prev := days[5].(map[string]any)
	if last["date"] != "2026-12-01" || last["seconds"] != float64(1800) || prev["date"] != "2026-11-30" || prev["seconds"] != float64(600) {
		t.Errorf("unexpected daily totals: %v", days)
	}

	// The same data in UTC: 1 Dec UTC starts after the 00:15 IST session.
	e.do("PUT", "/v1/me/preferences", u.token, map[string]any{"timezone": "UTC", "dailyTargetMinutes": 360, "weeklyTargetMinutes": 3000})
	_, s, _ = e.do("GET", "/v1/stats/summary", u.token, nil)
	if s["todaySeconds"] != float64(0) || s["timezone"] != "UTC" {
		t.Errorf("UTC summary: todaySeconds = %v, timezone = %v", s["todaySeconds"], s["timezone"])
	}
}

func TestConcurrentWritesKeepChangeFeedConsistent(t *testing.T) {
	e := newEnv(t)
	u := e.newUser("race@example.com")
	e.do("GET", "/v1/me", u.token, nil)

	replayID := uuid.NewString()
	var wg sync.WaitGroup
	statuses := make(chan int, 40)
	for i := range 25 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			s, _, _ := e.do("PUT", "/v1/study-sessions/"+uuid.NewString(), u.token,
				session(fixedNow.Add(-time.Duration(i+1)*time.Minute*10), 300, fixedNow))
			statuses <- s
		}()
	}
	for range 10 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			s, _, _ := e.do("PUT", "/v1/study-sessions/"+replayID, u.token, session(fixedNow.Add(-5*time.Hour), 300, fixedNow))
			statuses <- s
		}()
	}
	wg.Wait()
	close(statuses)
	created := 0
	for s := range statuses {
		switch s {
		case 201:
			created++
		case 200:
		default:
			t.Fatalf("unexpected status %d under concurrency", s)
		}
	}
	if created != 26 {
		t.Fatalf("created = %d, want 26 (25 distinct + 1 replayed id)", created)
	}
	_, feed, _ := e.do("GET", "/v1/sync/study-sessions?limit=1000", u.token, nil)
	changes := feed["changes"].([]any)
	if len(changes) != 26 {
		t.Fatalf("feed has %d changes, want 26", len(changes))
	}
	last := 0.0
	for _, c := range changes {
		seq := c.(map[string]any)["changeSeq"].(float64)
		if seq <= last {
			t.Fatalf("changeSeq not strictly increasing: %v after %v", seq, last)
		}
		last = seq
	}
}

func TestCORSIsOffUnlessOriginsConfigured(t *testing.T) {
	st := testutil.NewStore(t)
	iss := testutil.NewIssuer(t)
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	v, err := auth.NewJWKSVerifier(ctx, iss.JWKSURL(), iss.Origin, iss.Origin)
	if err != nil {
		t.Fatal(err)
	}
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	preflight := func(h http.Handler, origin string) string {
		req := httptest.NewRequest(http.MethodOptions, "/v1/me", nil)
		req.Header.Set("Origin", origin)
		req.Header.Set("Access-Control-Request-Method", "GET")
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, req)
		return rec.Header().Get("Access-Control-Allow-Origin")
	}

	native := httpapi.New(st, v, log, httpapi.Options{})
	if got := preflight(native, "https://evil.example"); got != "" {
		t.Fatalf("CORS must be off by default, got Allow-Origin %q", got)
	}

	browser := httpapi.New(st, v, log, httpapi.Options{CORSOrigins: []string{"https://app.example"}})
	if got := preflight(browser, "https://app.example"); got != "https://app.example" {
		t.Fatalf("listed origin not allowed: %q", got)
	}
	if got := preflight(browser, "https://evil.example"); got != "" {
		t.Fatalf("unlisted origin allowed: %q", got)
	}
}
