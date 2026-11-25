// Package testutil provides a real PostgreSQL database and a real JWKS issuer
// for integration tests. Nothing is mocked: tokens are Ed25519-signed and
// verified via HTTP-fetched JWKS, and queries run against PostgreSQL.
package testutil

import (
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"sync"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"

	"github.com/eagle-engineering/ecosystem/api/internal/store"
)

const defaultTestDB = "postgres://eagle:eagle_dev_password@localhost:5434/eagle_test?sslmode=disable"

var migrateOnce sync.Once

// DatabaseURL returns TEST_DATABASE_URL or the docker-compose test database.
func DatabaseURL() string {
	if u := os.Getenv("TEST_DATABASE_URL"); u != "" {
		return u
	}
	return defaultTestDB
}

// NewStore migrates (once per process) and truncates the test database.
// Tests using it must not run in parallel with each other.
func NewStore(t *testing.T) *store.Store {
	t.Helper()
	var migErr error
	migrateOnce.Do(func() { migErr = store.Migrate(DatabaseURL()) })
	if migErr != nil {
		t.Fatalf("migrate test database (is `docker compose up` running?): %v", migErr)
	}
	ctx := context.Background()
	st, err := store.Open(ctx, DatabaseURL())
	if err != nil {
		t.Fatalf("open test database: %v", err)
	}
	t.Cleanup(st.Close)
	if _, err := st.Pool().Exec(ctx,
		`TRUNCATE users, user_preferences, study_sessions, study_session_audit RESTART IDENTITY CASCADE`); err != nil {
		t.Fatalf("truncate: %v", err)
	}
	return st
}

// Issuer is an in-process stand-in for Neon Auth's JWKS endpoint.
type Issuer struct {
	Server  *httptest.Server
	Origin  string
	kid     string
	private ed25519.PrivateKey
}

func NewIssuer(t *testing.T) *Issuer {
	t.Helper()
	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	iss := &Issuer{kid: uuid.NewString(), private: priv}
	iss.Server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{"keys": []map[string]string{{
			"kty": "OKP", "crv": "Ed25519", "alg": "EdDSA", "use": "sig", "kid": iss.kid,
			"x": base64.RawURLEncoding.EncodeToString(pub),
		}}})
	}))
	iss.Origin = iss.Server.URL
	t.Cleanup(iss.Server.Close)
	return iss
}

func (i *Issuer) JWKSURL() string { return i.Server.URL + "/.well-known/jwks.json" }

// TokenOption mutates claims before signing, to build invalid tokens.
type TokenOption func(jwt.MapClaims)

func WithClaim(key string, value any) TokenOption {
	return func(c jwt.MapClaims) { c[key] = value }
}

// Token mints a Neon-Auth-shaped token for userID.
func (i *Issuer) Token(t *testing.T, userID uuid.UUID, email string, opts ...TokenOption) string {
	t.Helper()
	return i.sign(t, i.private, userID, email, opts...)
}

// ForeignToken is signed by a key that is NOT in the JWKS.
func (i *Issuer) ForeignToken(t *testing.T, userID uuid.UUID, email string) string {
	t.Helper()
	_, other, _ := ed25519.GenerateKey(rand.Reader)
	return i.sign(t, other, userID, email)
}

func (i *Issuer) sign(t *testing.T, key ed25519.PrivateKey, userID uuid.UUID, email string, opts ...TokenOption) string {
	now := time.Now()
	claims := jwt.MapClaims{
		"sub": userID.String(), "email": email, "name": "Test User", "emailVerified": true,
		"banned": false, "iss": i.Origin, "aud": i.Origin,
		"iat": now.Unix(), "exp": now.Add(15 * time.Minute).Unix(),
	}
	for _, opt := range opts {
		opt(claims)
	}
	tok := jwt.NewWithClaims(jwt.SigningMethodEdDSA, claims)
	tok.Header["kid"] = i.kid
	s, err := tok.SignedString(key)
	if err != nil {
		t.Fatal(err)
	}
	return s
}
