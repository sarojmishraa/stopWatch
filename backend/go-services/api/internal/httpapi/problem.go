package httpapi

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"strings"

	"github.com/go-chi/chi/v5/middleware"

	"github.com/eagle-engineering/ecosystem/api/internal/auth"
)

// Problem is an RFC 9457 (formerly 7807) problem details response.
type Problem struct {
	Type      string       `json:"type"`
	Title     string       `json:"title"`
	Status    int          `json:"status"`
	Detail    string       `json:"detail,omitempty"`
	RequestID string       `json:"requestId,omitempty"`
	Errors    []FieldError `json:"errors,omitempty"`
	// Current carries the server's version of a record on a 409 so an
	// offline client can reconcile without another round trip.
	Current any `json:"current,omitempty"`
}

type FieldError struct {
	Field   string `json:"field"`
	Message string `json:"message"`
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func writeProblem(w http.ResponseWriter, r *http.Request, p Problem) {
	if p.Type == "" {
		p.Type = "about:blank"
	}
	if p.Title == "" {
		p.Title = http.StatusText(p.Status)
	}
	p.RequestID = middleware.GetReqID(r.Context())
	w.Header().Set("Content-Type", "application/problem+json")
	w.WriteHeader(p.Status)
	_ = json.NewEncoder(w).Encode(p)
}

func validationProblem(w http.ResponseWriter, r *http.Request, errs []FieldError) {
	writeProblem(w, r, Problem{
		Type:   "https://eagle.study/problems/validation",
		Title:  "Request validation failed",
		Status: http.StatusUnprocessableEntity,
		Errors: errs,
	})
}

func (a *API) internalError(w http.ResponseWriter, r *http.Request, err error) {
	a.log.ErrorContext(r.Context(), "request failed",
		"err", err, "path", r.URL.Path, "request_id", middleware.GetReqID(r.Context()))
	writeProblem(w, r, Problem{
		Status: http.StatusInternalServerError,
		Detail: "An unexpected error occurred. Quote the request ID if you report this.",
	})
}

func authError(log *slog.Logger) func(http.ResponseWriter, *http.Request, error) {
	return func(w http.ResponseWriter, r *http.Request, err error) {
		if errors.Is(err, auth.ErrBanned) {
			writeProblem(w, r, Problem{Status: http.StatusForbidden, Detail: "This account is suspended."})
			return
		}
		log.InfoContext(r.Context(), "authentication rejected", "reason", err.Error(),
			"request_id", middleware.GetReqID(r.Context()))
		w.Header().Set("WWW-Authenticate", `Bearer error="invalid_token"`)
		detail := "Sign in again: the access token is missing, invalid or expired."
		if errors.Is(err, auth.ErrMissingToken) {
			w.Header().Set("WWW-Authenticate", `Bearer`)
			detail = "This endpoint requires an Authorization: Bearer <token> header."
		}
		writeProblem(w, r, Problem{Status: http.StatusUnauthorized, Detail: detail})
	}
}

const maxBodyBytes = 1 << 20

// decodeJSON decodes exactly one JSON object and rejects unknown fields, so a
// typo in a client field name fails loudly instead of being silently dropped.
func decodeJSON(w http.ResponseWriter, r *http.Request, dst any) bool {
	if ct := r.Header.Get("Content-Type"); ct != "" && !strings.HasPrefix(ct, "application/json") {
		writeProblem(w, r, Problem{Status: http.StatusUnsupportedMediaType, Detail: "Send application/json."})
		return false
	}
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxBodyBytes))
	dec.DisallowUnknownFields()
	if err := dec.Decode(dst); err != nil {
		var tooLarge *http.MaxBytesError
		if errors.As(err, &tooLarge) {
			writeProblem(w, r, Problem{Status: http.StatusRequestEntityTooLarge, Detail: "Request body exceeds 1 MiB."})
			return false
		}
		writeProblem(w, r, Problem{Status: http.StatusBadRequest, Detail: fmt.Sprintf("Malformed JSON body: %v", err)})
		return false
	}
	if err := dec.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		writeProblem(w, r, Problem{Status: http.StatusBadRequest, Detail: "Body must contain a single JSON object."})
		return false
	}
	return true
}
