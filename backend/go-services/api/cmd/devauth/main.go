// Command devauth is a LOCAL DEVELOPMENT ONLY stand-in for Neon Auth.
//
// It mints EdDSA (Ed25519) JWTs with the same claim shape Neon Auth uses
// (sub, email, name, emailVerified, iss = aud = origin, 15-minute expiry) and
// serves the public key at /.well-known/jwks.json, so the API runs its real
// verification path without a cloud account. It performs no password check,
// and so it refuses to listen on anything but loopback.
//
//	go run ./cmd/devauth
//	curl -s -X POST localhost:8787/token -d '{"email":"me@example.com","name":"Me"}'
package main

import (
	"crypto/ed25519"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"log"
	"net"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
)

// Fixed namespace so the same email always maps to the same user ID locally.
var userNamespace = uuid.MustParse("6f1c2b8e-2f0e-4b8a-9a52-1c7e5d1f3a90")

func main() {
	addr := os.Getenv("DEVAUTH_ADDR")
	if addr == "" {
		addr = "127.0.0.1:8787"
	}
	host, port, err := net.SplitHostPort(addr)
	if err != nil {
		log.Fatalf("DEVAUTH_ADDR: %v", err)
	}
	if ip := net.ParseIP(host); host != "localhost" && (ip == nil || !ip.IsLoopback()) {
		log.Fatalf("devauth only listens on loopback (got %q); use Neon Auth for anything else", host)
	}
	origin := "http://localhost:" + port

	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		log.Fatal(err)
	}
	kid := uuid.NewString()

	mux := http.NewServeMux()
	mux.HandleFunc("GET /.well-known/jwks.json", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{"keys": []map[string]string{{
			"kty": "OKP", "crv": "Ed25519", "alg": "EdDSA", "use": "sig", "kid": kid,
			"x": base64.RawURLEncoding.EncodeToString(pub),
		}}})
	})
	mux.HandleFunc("POST /token", func(w http.ResponseWriter, r *http.Request) {
		var body struct{ Email, Name string }
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096)).Decode(&body); err != nil ||
			!strings.Contains(body.Email, "@") {
			http.Error(w, `body must be {"email":"you@example.com","name":"optional"}`, http.StatusBadRequest)
			return
		}
		email := strings.ToLower(strings.TrimSpace(body.Email))
		sub := uuid.NewSHA1(userNamespace, []byte(email)).String()
		now := time.Now()
		tok := jwt.NewWithClaims(jwt.SigningMethodEdDSA, jwt.MapClaims{
			"sub": sub, "id": sub, "email": email, "name": body.Name, "emailVerified": true,
			"role": "authenticated", "banned": false,
			"iss": origin, "aud": origin, "iat": now.Unix(), "exp": now.Add(15 * time.Minute).Unix(),
		})
		tok.Header["kid"] = kid
		signed, err := tok.SignedString(priv)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{"token": signed, "userId": sub, "expiresIn": 900})
	})

	log.Printf("devauth (LOCAL ONLY) on %s — set AUTH_JWKS_URL=%s/.well-known/jwks.json AUTH_ISSUER=%s AUTH_AUDIENCE=%s",
		addr, origin, origin, origin)
	log.Fatal((&http.Server{Addr: addr, Handler: mux, ReadHeaderTimeout: 5 * time.Second}).ListenAndServe())
}
