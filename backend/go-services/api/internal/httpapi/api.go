// Package httpapi exposes the REST API described in
// backend/api-contracts/openapi.yaml.
package httpapi

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"strconv"
	"sync"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/go-chi/cors"
	"github.com/google/uuid"

	"github.com/eagle-engineering/ecosystem/api/internal/auth"
	"github.com/eagle-engineering/ecosystem/api/internal/store"
)

type API struct {
	store    *store.Store
	verifier *auth.Verifier
	log      *slog.Logger
	now      func() time.Time
	// knownUsers avoids an upsert on every request; the first authenticated
	// request per user per process creates/refreshes the users row.
	knownUsers sync.Map
}

type Options struct {
	CORSOrigins []string
	Now         func() time.Time
}

func New(st *store.Store, v *auth.Verifier, log *slog.Logger, opts Options) http.Handler {
	a := &API{store: st, verifier: v, log: log, now: time.Now}
	if opts.Now != nil {
		a.now = opts.Now
	}

	r := chi.NewRouter()
	r.Use(requestID)
	r.Use(a.accessLog)
	r.Use(middleware.Recoverer)
	r.Use(middleware.Timeout(15 * time.Second))
	r.Use(securityHeaders)
	// The Android app is a native client and needs no CORS. Only enable it
	// for explicitly listed browser origins: go-chi/cors treats an empty
	// list as "allow every origin", which must never happen by default.
	if len(opts.CORSOrigins) > 0 {
		r.Use(cors.Handler(cors.Options{
			AllowedOrigins: opts.CORSOrigins,
			AllowedMethods: []string{http.MethodGet, http.MethodPut, http.MethodPost, http.MethodDelete, http.MethodOptions},
			AllowedHeaders: []string{"Authorization", "Content-Type"},
			ExposedHeaders: []string{"X-Request-Id"},
			MaxAge:         600,
		}))
	}

	r.Get("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})
	r.Get("/readyz", a.ready)

	r.Route("/v1", func(r chi.Router) {
		r.Use(auth.Middleware(v, authError(log)))
		r.Use(a.ensureUser)

		r.Get("/me", a.getMe)
		r.Put("/me/preferences", a.putPreferences)

		r.Get("/study-sessions", a.listSessions)
		r.Get("/study-sessions/{id}", a.getSession)
		r.Put("/study-sessions/{id}", a.putSession)
		r.Delete("/study-sessions/{id}", a.deleteSession)

		r.Get("/sync/study-sessions", a.sessionChanges)
		r.Get("/stats/summary", a.summary)
	})

	r.NotFound(func(w http.ResponseWriter, r *http.Request) {
		writeProblem(w, r, Problem{Status: http.StatusNotFound, Detail: "No such endpoint."})
	})
	r.MethodNotAllowed(func(w http.ResponseWriter, r *http.Request) {
		writeProblem(w, r, Problem{Status: http.StatusMethodNotAllowed})
	})
	return r
}

func (a *API) ready(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()
	if err := a.store.Ping(ctx); err != nil {
		a.log.WarnContext(r.Context(), "readiness check failed", "err", err)
		writeProblem(w, r, Problem{Status: http.StatusServiceUnavailable, Detail: "Database unavailable."})
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ready"})
}

func (a *API) ensureUser(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		id, _ := auth.FromContext(r.Context())
		if _, seen := a.knownUsers.Load(id.UserID); !seen {
			if _, err := a.store.EnsureUser(r.Context(), id.UserID, id.Email, id.Name); err != nil {
				a.internalError(w, r, err)
				return
			}
			a.knownUsers.Store(id.UserID, struct{}{})
		}
		next.ServeHTTP(w, r)
	})
}

func (a *API) getMe(w http.ResponseWriter, r *http.Request) {
	id, _ := auth.FromContext(r.Context())
	u, err := a.store.EnsureUser(r.Context(), id.UserID, id.Email, id.Name)
	if err != nil {
		a.internalError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, u)
}

func (a *API) putPreferences(w http.ResponseWriter, r *http.Request) {
	id, _ := auth.FromContext(r.Context())
	var body preferencesBody
	if !decodeJSON(w, r, &body) {
		return
	}
	prefs, errs := body.validate()
	if errs != nil {
		validationProblem(w, r, errs)
		return
	}
	out, err := a.store.UpdatePreferences(r.Context(), id.UserID, prefs)
	if err != nil {
		a.internalError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, out)
}

func (a *API) putSession(w http.ResponseWriter, r *http.Request) {
	id, _ := auth.FromContext(r.Context())
	sessionID, ok := pathUUID(w, r)
	if !ok {
		return
	}
	var body sessionBody
	if !decodeJSON(w, r, &body) {
		return
	}
	in, errs := body.validate(sessionID, a.now())
	if errs != nil {
		validationProblem(w, r, errs)
		return
	}
	out, outcome, err := a.store.PutSession(r.Context(), id.UserID, in)
	switch {
	case errors.Is(err, store.ErrConflict):
		writeProblem(w, r, Problem{
			Type:    "https://eagle.study/problems/conflict",
			Title:   "Newer version on server",
			Status:  http.StatusConflict,
			Detail:  "The server holds a newer or deleted version of this session; reconcile using `current`.",
			Current: out,
		})
	case errors.Is(err, store.ErrIDTaken):
		writeProblem(w, r, Problem{Status: http.StatusConflict, Detail: "This session ID cannot be used; generate a new UUID."})
	case err != nil:
		a.internalError(w, r, err)
	case outcome == store.Created:
		w.Header().Set("Location", "/v1/study-sessions/"+out.ID.String())
		writeJSON(w, http.StatusCreated, out)
	default:
		writeJSON(w, http.StatusOK, out)
	}
}

func (a *API) getSession(w http.ResponseWriter, r *http.Request) {
	id, _ := auth.FromContext(r.Context())
	sessionID, ok := pathUUID(w, r)
	if !ok {
		return
	}
	out, err := a.store.GetSession(r.Context(), id.UserID, sessionID)
	if errors.Is(err, store.ErrNotFound) {
		writeProblem(w, r, Problem{Status: http.StatusNotFound, Detail: "Study session not found."})
		return
	}
	if err != nil {
		a.internalError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, out)
}

func (a *API) deleteSession(w http.ResponseWriter, r *http.Request) {
	id, _ := auth.FromContext(r.Context())
	sessionID, ok := pathUUID(w, r)
	if !ok {
		return
	}
	err := a.store.DeleteSession(r.Context(), id.UserID, sessionID)
	if errors.Is(err, store.ErrNotFound) {
		writeProblem(w, r, Problem{Status: http.StatusNotFound, Detail: "Study session not found."})
		return
	}
	if err != nil {
		a.internalError(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (a *API) listSessions(w http.ResponseWriter, r *http.Request) {
	id, _ := auth.FromContext(r.Context())
	q := r.URL.Query()
	now := a.now()
	var errs []FieldError
	from := parseTime(q.Get("from"), now.AddDate(0, 0, -30), "from", &errs)
	to := parseTime(q.Get("to"), now.Add(maxClockSkew), "to", &errs)
	limit := parseInt(q.Get("limit"), 100, 1, 500, "limit", &errs)
	if !from.Before(to) && errs == nil {
		errs = append(errs, FieldError{"from", "must be before to"})
	}
	if errs != nil {
		validationProblem(w, r, errs)
		return
	}
	out, err := a.store.ListSessions(r.Context(), id.UserID, from, to, int(limit))
	if err != nil {
		a.internalError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"sessions": out})
}

func (a *API) sessionChanges(w http.ResponseWriter, r *http.Request) {
	id, _ := auth.FromContext(r.Context())
	q := r.URL.Query()
	var errs []FieldError
	since := parseInt(q.Get("since"), 0, 0, 1<<62, "since", &errs)
	limit := parseInt(q.Get("limit"), 500, 1, 1000, "limit", &errs)
	if errs != nil {
		validationProblem(w, r, errs)
		return
	}
	changes, hasMore, err := a.store.SessionChanges(r.Context(), id.UserID, since, int(limit))
	if err != nil {
		a.internalError(w, r, err)
		return
	}
	next := since
	if n := len(changes); n > 0 {
		next = changes[n-1].ChangeSeq
	}
	writeJSON(w, http.StatusOK, map[string]any{"changes": changes, "nextCursor": next, "hasMore": hasMore})
}

func (a *API) summary(w http.ResponseWriter, r *http.Request) {
	id, _ := auth.FromContext(r.Context())
	out, err := a.store.Summary(r.Context(), id.UserID)
	if err != nil {
		a.internalError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, out)
}

func pathUUID(w http.ResponseWriter, r *http.Request) (uuid.UUID, bool) {
	id, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		writeProblem(w, r, Problem{Status: http.StatusBadRequest, Detail: "Path id must be a UUID."})
		return uuid.UUID{}, false
	}
	return id, true
}

func parseTime(raw string, fallback time.Time, field string, errs *[]FieldError) time.Time {
	if raw == "" {
		return fallback
	}
	t, err := time.Parse(time.RFC3339Nano, raw)
	if err != nil {
		*errs = append(*errs, FieldError{field, "must be an RFC 3339 timestamp"})
	}
	return t
}

func parseInt(raw string, fallback, minimum, maximum int64, field string, errs *[]FieldError) int64 {
	if raw == "" {
		return fallback
	}
	n, err := strconv.ParseInt(raw, 10, 64)
	if err != nil || n < minimum || n > maximum {
		*errs = append(*errs, FieldError{field, "must be an integer between " +
			strconv.FormatInt(minimum, 10) + " and " + strconv.FormatInt(maximum, 10)})
	}
	return n
}

// requestID assigns a random ID per request. chi's default embeds the host
// name, which would leak infrastructure details in every error response.
// Client-supplied IDs are ignored so log correlation cannot be spoofed.
func requestID(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ctx := context.WithValue(r.Context(), middleware.RequestIDKey, uuid.NewString())
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func securityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h := w.Header()
		h.Set("X-Content-Type-Options", "nosniff")
		h.Set("Referrer-Policy", "no-referrer")
		h.Set("Cache-Control", "no-store")
		next.ServeHTTP(w, r)
	})
}

func (a *API) accessLog(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ww := middleware.NewWrapResponseWriter(w, r.ProtoMajor)
		ww.Header().Set("X-Request-Id", middleware.GetReqID(r.Context()))
		start := time.Now()
		next.ServeHTTP(ww, r)
		route := r.URL.Path
		if rc := chi.RouteContext(r.Context()); rc != nil && rc.RoutePattern() != "" {
			route = rc.RoutePattern() // avoid logging user IDs embedded in paths
		}
		a.log.InfoContext(r.Context(), "http",
			"method", r.Method, "route", route, "status", ww.Status(),
			"duration_ms", time.Since(start).Milliseconds(),
			"request_id", middleware.GetReqID(r.Context()))
	})
}
