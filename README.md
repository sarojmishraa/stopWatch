# Eagle Engineering Ecosystem

One Flutter Android app on a Go + PostgreSQL backend:

- **EAGLE STUDY** ([apps/eagle-study-android](apps/eagle-study-android)): a study timer with alarms, Study Mode and a 3D eagle, plus the 12-month Distributed Systems Engineer learning dashboard (roadmap, calendar, DSA/Java/Go tracking, analytics). It works offline on SQLite and syncs to the API.
- **API** ([backend/go-services/api](backend/go-services/api)): Go + PostgreSQL. Identity comes from Neon Auth.

Read [ARCHITECTURE.md](documentation/architecture/ARCHITECTURE.md) for the design and [IMPLEMENTATION_CHECKLIST.md](IMPLEMENTATION_CHECKLIST.md) for what is actually done.

## Prerequisites

Docker, Go ≥ 1.27, Flutter ≥ 3.47 (Dart ≥ 3.13, Android SDK).

## Run locally

```bash
cp .env.example .env
make db-up        # PostgreSQL 17 on localhost:5434 (databases: eagle, eagle_test)
make devauth      # terminal 1: local stand-in for Neon Auth (loopback only)
make api          # terminal 2: API on :8080, applies migrations on start

# Get a dev token and call the API
TOKEN=$(curl -s -X POST localhost:8787/token -d '{"email":"me@example.com"}' | jq -r .token)
curl -s localhost:8080/v1/me -H "Authorization: Bearer $TOKEN"
```

To use real Neon Auth instead, set `NEON_AUTH_BASE_URL` in `.env` and remove the three `AUTH_*` lines.

## Test

```bash
make test-api     # Go integration tests against real PostgreSQL, with -race
make test-app     # flutter analyze + flutter test
```

## Layout

```
apps/            eagle-study-android (Flutter)
backend/         go-services/api · java-services (planned) · api-contracts/openapi.yaml
infrastructure/  docker · kubernetes · terraform · ci-cd
documentation/   architecture · api · deployment · roadmap · testing
```
