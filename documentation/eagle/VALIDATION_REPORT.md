# Eagle Study 3D integration validation

Date: 2026-11-26 (Asia/Kolkata).

## Scope and result

The user confirmed **prepare integration and model pipeline** because they do
not currently have a licensed realistic golden-eagle model. The Flutter
integration and asset intake tools are implemented. **The photorealistic eagle,
its authored rig, textures, `.blend` source and eight animation clips are not
delivered or verified.** No placeholder `.glb` was created.

The pre-existing worktree already contained an unfinished native Filament eagle
implementation, four mood states, bald-eagle attribution, and no model binary.
It played animation index 0 at different speeds and could not fulfill the named
clip contract. That code and unrelated Go/app changes were preserved. The
dashboard now selects the added Flutter Scene widget. Legacy Filament libraries
remain in the Android build and can be removed in a separate cleanup once the
new renderer is verified on hardware.

## Environment inspected

| Item | Observed |
| --- | --- |
| GPU | Apple M1, 7 cores, Metal supported |
| Flutter | 3.47.5 stable |
| Dart | 3.13.4 |
| Go | 1.27.4 |
| Blender | Not installed |
| Flutter Scene | 0.24.6, pinned and resolved |
| Android device/emulator | None attached; no configured emulators |
| Production model | `assets/3d/eagle_mascot.glb` absent |

[Flutter Scene 0.24.6](https://pub.dev/packages/flutter_scene/versions/0.24.6)
declares Flutter ≥3.47 and Android support. The downloaded package source was
inspected for loading, animation, blending, disposal and template-cache release.
Android Flutter GPU metadata and the package-generated asset build hook are in
place. Compatibility at dependency/build level does not prove GPU rendering on
the requested Android 10–16 range.

## Checks run

| Check | Result |
| --- | --- |
| Baseline Flutter analysis | Passed before implementation |
| Integration Flutter analysis | Passed, no issues |
| Full Flutter suite | 69 tests passed |
| Python GLB validator tests | 13 passed |
| Blender exporter/Python validator syntax | Passed; not Blender runtime execution |
| Android rendering probe | Debug ARM64 APK built successfully |
| Full study app | Debug ARM64 APK built successfully |
| Go `go vet ./...` | Passed; no backend changes |
| `git diff --check` | Passed |
| Missing production GLB | Validator correctly returns failure |

New tests cover startup/study/break/save transitions, stale completion rejection,
replay IDs, loop overrides, preference persistence and write ordering, missing
model fallback and reduced-motion behavior. Validator fixtures cover malformed
headers/chunks, missing bones/clips, duplicate or static animation data, invalid
material/accessor references, hierarchy cycles, zero skin weights, external
textures and unverified compression. Synthetic fixtures are parser test data,
not proof of eagle appearance or animation quality.

Commands (from the relevant app/API directory unless shown otherwise):

```sh
flutter analyze
flutter test --reporter expanded
flutter build apk --debug --target-platform android-arm64 -t lib/eagle_scene_probe.dart
flutter build apk --debug --target-platform android-arm64 -t lib/main.dart
go vet ./...
# From repository root:
python3 -B -m unittest discover -s tools/eagle -p 'test_*.py' -v
git diff --check
```

The rendering probe uses a labelled PBR cube. It compiled but was not run on
Android. There is no captured rendered frame, model playback recording, GPU
memory measurement or frame-time trace. Go database integration tests were not
run; this task does not change the backend.

## Required model and device checks still pending

| Requested validation | Status and next evidence |
| --- | --- |
| GLB loads successfully | Pending artist asset, structural validation and runtime load |
| All textures load | Pending embedded image decode and rendered inspection |
| Skeleton exists | Required by validator; no production skeleton available |
| All eight names exist | Contract implemented; no production clips available |
| Clips play independently | Controller tested; actual imported clip playback pending |
| No broken geometry | Bounds/weights/degenerate checks prepared; visual QA pending |
| No missing materials | Reference/PBR checks prepared; production material QA pending |
| Realistic golden-eagle appearance | Requires licensed source, artist work and visual approval |
| Android renderer displays eagle | Pending model and connected device |
| 60 FPS / memory / thermals | Target only; no hardware measurements |
| Blender export | Script syntax/API review only; execution pending Blender and source |

On Android 10 and 16 plus at least one mid-range device, run the probe first,
then the real model. Play all eight clips, interrupt one-shots, start/pause/finish
study, disable/re-enable 3D, background/foreground, navigate away/back, and enable
reduced motion. Capture the frame and logs after loading settles. Check full
wing-extension framing and feather transparency. Profile frame timing, peak
memory, repeated view creation/disposal and a sustained study session. Report
device/OS, render resolution, measured FPS/frame percentiles and memory rather
than declaring the 60 FPS target achieved from a build.

Instructions: [production pipeline](../../tools/eagle/README.md) and
[animation contract](ANIMATIONS.md).
