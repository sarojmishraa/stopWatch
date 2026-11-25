// Package auth verifies Neon Auth (Managed Better Auth) JWTs and exposes the
// caller's identity to HTTP handlers.
//
// Neon Auth signs tokens with EdDSA (Ed25519), sets iss and aud to the origin
// of the auth URL, and publishes public keys at <auth-url>/.well-known/jwks.json.
// Tokens live 15 minutes, so clients refresh them through the Neon Auth SDK.
package auth

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/MicahParks/keyfunc/v3"
	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
)

// Identity is the verified caller.
type Identity struct {
	UserID        uuid.UUID
	Email         string
	Name          string
	EmailVerified bool
}

type claims struct {
	jwt.RegisteredClaims
	Email         string `json:"email"`
	Name          string `json:"name"`
	EmailVerified bool   `json:"emailVerified"`
	Banned        bool   `json:"banned"`
}

var (
	ErrMissingToken = errors.New("missing bearer token")
	ErrInvalidToken = errors.New("invalid or expired token")
	ErrBanned       = errors.New("account is banned")
)

type Verifier struct {
	keys     jwt.Keyfunc
	issuer   string
	audience string
}

// NewJWKSVerifier fetches and caches the JWKS, refreshing it in the
// background and on unknown key IDs (key rotation). The background refresh
// stops when ctx is cancelled.
func NewJWKSVerifier(ctx context.Context, jwksURL, issuer, audience string) (*Verifier, error) {
	kf, err := keyfunc.NewDefaultCtx(ctx, []string{jwksURL})
	if err != nil {
		return nil, fmt.Errorf("load JWKS from %s: %w", jwksURL, err)
	}
	return &Verifier{keys: kf.Keyfunc, issuer: issuer, audience: audience}, nil
}

func (v *Verifier) Verify(raw string) (Identity, error) {
	var c claims
	_, err := jwt.ParseWithClaims(raw, &c, v.keys,
		jwt.WithValidMethods([]string{"EdDSA"}),
		jwt.WithIssuer(v.issuer),
		jwt.WithAudience(v.audience),
		jwt.WithExpirationRequired(),
		jwt.WithIssuedAt(),
		jwt.WithLeeway(30*time.Second),
	)
	if err != nil {
		return Identity{}, fmt.Errorf("%w: %v", ErrInvalidToken, err)
	}
	if c.Banned {
		return Identity{}, ErrBanned
	}
	id, err := uuid.Parse(c.Subject)
	if err != nil {
		return Identity{}, fmt.Errorf("%w: subject is not a UUID", ErrInvalidToken)
	}
	if strings.TrimSpace(c.Email) == "" {
		return Identity{}, fmt.Errorf("%w: email claim missing", ErrInvalidToken)
	}
	return Identity{UserID: id, Email: c.Email, Name: c.Name, EmailVerified: c.EmailVerified}, nil
}

type ctxKey struct{}

func WithIdentity(ctx context.Context, id Identity) context.Context {
	return context.WithValue(ctx, ctxKey{}, id)
}

// FromContext returns the identity placed by Middleware. Handlers behind the
// middleware can rely on ok being true.
func FromContext(ctx context.Context) (Identity, bool) {
	id, ok := ctx.Value(ctxKey{}).(Identity)
	return id, ok
}

func BearerToken(r *http.Request) (string, error) {
	h := r.Header.Get("Authorization")
	scheme, token, found := strings.Cut(h, " ")
	if !found || !strings.EqualFold(scheme, "Bearer") || strings.TrimSpace(token) == "" {
		return "", ErrMissingToken
	}
	return strings.TrimSpace(token), nil
}

// Middleware rejects unauthenticated requests. onError writes the response so
// the HTTP layer controls the error format.
func Middleware(v *Verifier, onError func(http.ResponseWriter, *http.Request, error)) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			raw, err := BearerToken(r)
			if err != nil {
				onError(w, r, err)
				return
			}
			id, err := v.Verify(raw)
			if err != nil {
				onError(w, r, err)
				return
			}
			next.ServeHTTP(w, r.WithContext(WithIdentity(r.Context(), id)))
		})
	}
}
