# Implementation checklist

Legend: ✅ done and tested · 🟡 partial (see note) · ⬜ not started

A box is ticked only when its implementation exists **and** its automated tests pass.

## Phase 1: Foundation
- ✅ Monorepo layout (`apps/`, `backend/`, `infrastructure/`, `documentation/`)
- ✅ Architecture decisions recorded ([ARCHITECTURE.md](documentation/architecture/ARCHITECTURE.md))
- ✅ PostgreSQL 17 via Docker Compose (dev + `eagle_test` databases, port 5434)
- ✅ Go API: config, structured JSON logs, graceful shutdown, health/readiness probes
- ✅ Neon Auth JWT verification (EdDSA via JWKS, iss/aud/exp, banned → 403)
- ✅ Local dev token issuer (`cmd/devauth`, loopback only)
- ✅ Schema v1: users, preferences, study sessions, change feed, audit trigger
- ✅ Study session API: idempotent PUT, last-writer-wins conflicts, soft delete, list, sync feed
- ✅ Stats summary in the user's timezone (Asia/Kolkata default)
- ✅ OpenAPI 3.1 contract ([openapi.yaml](backend/api-contracts/openapi.yaml))
- ✅ Go integration tests on real Postgres: 12 tests incl. CORS-off-by-default, `-race`
- ✅ Flutter app moved, compile errors fixed, analyzer clean, 4 tests passing
- ✅ Scope decision: single Flutter Android app (Next.js dashboard dropped; see D9)
- ⬜ CI pipeline (GitHub Actions: Go tests with a Postgres service, Flutter analyze/test)
- ⬜ Git repository initialised (the folder is not under version control yet)

## Phase 2: EAGLE STUDY dashboard, stopwatch, countdown, local storage
- 🟡 Timestamp-anchored stopwatch/countdown with persisted state (existing; unit-tested)
- 🟡 Presets 5/15/25/45/60/90 and custom H:M:S (existing UI; needs widget tests)
- ⬜ Client-generated session UUIDs + local outbox table for sync
- ⬜ Lap history per session persisted (currently lost on finish)
- ⬜ Session history screen

## Phase 3: Alarm engine (Kotlin)
- ⬜ AlarmManager exact alarms + SCHEDULE_EXACT_ALARM flow, notification channels
- ⬜ Boot / time-change / package-replaced rescheduling
- ⬜ Audio focus, volume, previews, custom voice recording
- ⬜ Licensed or original alarm sound assets

## Phase 4: Study Mode
- ⬜ Foreground service (`specialUse`/`shortService` evaluation) with notification controls
- ⬜ Keep-screen-awake option
- ⬜ DND policy access flow with restore of previous filter

## Phase 5: 3D eagle
- ⬜ Blender eagle asset (modelled or licensed). **Blocked on an asset**
- ⬜ SceneView/Filament PlatformView, animation state machine, Rive fallback

## Phase 6: Learning dashboard (in the Flutter app)
- 🟡 Roadmap, schedule and sleep-health screens exist (prototype, local SQLite only)
- ⬜ Daily/weekly/monthly calendar with edit/reschedule/complete/undo/delete, all tested
- ⬜ Schema v2 in PostgreSQL: roadmap, tasks, DSA problems, topics, projects (+ sync)

## Phase 7: 3D roadmap (Flutter)
- 🟡 Projected sphere of 12 milestones exists (`roadmap_screen.dart`)
- ⬜ Drag-rotate, pinch-zoom, tap/long-press info cards, camera transitions, reset
- ⬜ Low-end device detection + accessible 2D fallback

## Phase 8: Learning content
- ⬜ Month-by-month curriculum with weekly milestones (sample content flagged as such)
- ⬜ Java, Go, DSA (Striver A2Z + LeetCode links), Distributed Systems, System Design, Platform modules

## Phase 9: Sync & analytics
- ⬜ Flutter Neon Auth integration (direct Better Auth HTTP; no official SDK)
- ⬜ Flutter outbox push + change-feed pull, conflict UI
- ⬜ `fl_chart` analytics: streaks, target vs actual, subject allocation, missed sessions

## Phase 10: Hardening & deployment
- ⬜ Row-level security, rate limiting, security audit
- ⬜ Neon production database + Neon Auth configuration
- ⬜ Container images, Kubernetes/Terraform, CI/CD, release-signed APK
- ⬜ Flutter integration tests on device, native Android tests, performance budgets
