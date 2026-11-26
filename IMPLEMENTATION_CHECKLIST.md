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
- ✅ Flutter app moved, compile errors fixed, analyzer clean
- ✅ Scope decision: single Flutter Android app (Next.js dashboard dropped; see D9)
- ⬜ CI pipeline (GitHub Actions: Go tests with a Postgres service, Flutter analyze/test)
- ✅ Git repository initialised

## Phase 2: EAGLE STUDY dashboard, stopwatch, countdown, local storage
- ✅ Timestamp-anchored stopwatch/countdown; state persisted and restored after process death (tested)
- ✅ Countdown that ends while the app is suspended or killed is saved with its real end time (tested)
- ✅ Session IDs assigned at start; save + timer clear in one SQLite transaction (no duplicates on crash/double tap; tested)
- ✅ SQLite schema v3 with the server's constraints; v2 → v3 migration of existing sessions (tested)
- ✅ Sync outbox: every save/edit/delete queued, one pending op per record (upload itself is Phase 9)
- ✅ Laps, subject, planned duration and real end time stored per session
- ✅ Totals in Asia/Kolkata (IANA rules; Monday weeks), daily 6 h and weekly 50 h targets shown with progress
- ✅ Session history screen: grouped by day, details and laps, edit subject/notes, delete with confirmation
- ✅ Presets 5/15/25/45/60/90 and custom H:M:S up to 24 h; discard confirmation for sessions over a minute
- ✅ 31 Flutter tests on real SQLite (unit, repository, migration, controller, widget)
- ⬜ Editable daily/weekly targets (fixed defaults for now)
- ⬜ Live foreground notification while the timer runs (Phase 4)

## Phase 3: Alarm engine (Kotlin)
- ✅ Native engine: AlarmManager `setAlarmClock` with exact-alarm permission, inexact fallback without it (JVM-tested scheduling)
- ✅ Foreground ringing service (mediaPlayback), wake lock, audio focus, ALARM stream, 5-minute auto-stop
- ✅ Full-screen lock-screen alarm (Android 14 permission checked) with Snooze 10 min / Dismiss; heads-up fallback
- ✅ Reboot, app-update, time and timezone change, and exact-alarm permission change re-register alarms
- ✅ Repeating (by weekday) and one-time alarms; one-time alarms turn off after ringing (reported back to Dart)
- ✅ Sounds: classic system tone, spoken message, ghost / monster / whisper voice styles (text-to-speech), own recording (≤30 s)
- ✅ Per-alarm message, volume, vibration, preview
- ✅ Focus countdown rings at its end even if the app is closed; pause/finish/reset cancel it (race-tested)
- ✅ Permission panel explains each permission before opening settings; OEM battery caveat shown
- ✅ Ad-ID permissions removed; Analytics runs without advertising identifiers
- ✅ Tests: 52 Flutter (incl. alarms domain, controller, screen) + 11 Kotlin JVM tests (same next-trigger cases as Dart)
- ⬜ On-device verification (Doze, reboot, lock screen, OEM battery managers): needs a phone, not done here
- ⬜ Horror laugh and cinematic eagle sounds: need original or licensed audio files

## Phase 4: Study Mode
- ✅ Immersive full-screen Study Mode: remaining/focused time, countdown progress, today vs daily goal, subject
- ✅ Session notification with live system chronometer and Pause / Resume / Finish (no foreground service needed)
- ✅ Notification Pause/Resume work even if the app was killed (native update of the saved timer, same rules as Dart; JVM-tested)
- ✅ Finish from the notification opens the app and saves the session there (validated, queued for sync)
- ✅ Keep-screen-on option, applied only while Study Mode is open
- ✅ Do Not Disturb: explicit access flow, Alarms-only / Priority-only, previous setting saved and restored on exit
- ✅ DND restore respects a manual change made during Study Mode, and self-heals after a crash
- ✅ Settings persisted; changing them while open re-applies immediately
- ✅ Tests: 62 Flutter (incl. Study Mode controller, notification sync, actions, screen) + 19 Kotlin
- ⬜ On-device verification (lock screen, DND on Android 15 "modes", OEM notification behaviour): needs a phone
- ⬜ Interactive eagle in Study Mode (Phase 5; a simple icon is shown for now)

## Phase 5: 3D eagle
- ✅ Model chosen: "Bald Eagle" by ucdavisterc (Sketchfab, CC BY 4.0); credits in-app (licence page) and assets/models/CREDITS.md
- ✅ Native renderer: Google Filament 1.81 (ModelViewer + gltfio) in a Flutter platform view, transparent, built-in lighting, 30 fps cap
- ✅ Moods from the study session: idle glide, focus flight, rest, 4 s celebration after a save; smooth blends; tap to react (JVM-tested)
- ✅ Automatic 2D fallback (no OpenGL ES 3.0, low-RAM phone, missing model, or load error); respects "Remove animations"
- ✅ Eagle on the timer dashboard and in Study Mode
- ✅ Release build verified: Filament native libs and JNI classes survive R8 (APK 26.7 MB, +6.7 MB)
- ⬜ Model file: waiting for the user to download the .glb from Sketchfab (sign-in required)
- ⬜ Texture downscaling + orientation/scale tuning once the model is in hand
- ⬜ On-device check of rendering, battery and frame rate
- ⬜ Only one animation exists in the free model: no true perch/landing clips (would need a paid or Blender-edited model)

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
- ⬜ API container image and deployment, CI, release-signed APK
- ⬜ Flutter integration tests on device, native Android tests, performance budgets
