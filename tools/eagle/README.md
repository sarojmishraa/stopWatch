# Golden-eagle production pipeline

This pipeline integrates an **artist-authored, licensed golden eagle**. It does
not generate a photorealistic animal from primitives, invent textures, or rename
one flight cycle eight times. The user selected **prepare integration and model
pipeline** on 2026-11-26 because no licensed model is currently available.

## Environment and setup

Inspected: Apple M1 (7-core Metal GPU), Flutter 3.47.5 stable, Dart 3.13.4,
Go 1.27.4. Blender and Android emulators are absent; no Android device is attached.

Install [Blender 4.5 LTS for Apple Silicon](https://www.blender.org/download/lts/),
open the downloaded DMG, and drag Blender into Applications. Verify:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --version
```

The scripts target Blender 4.5+ and inspect the exporter API before running.
They have only been syntax-checked here; Blender execution needs that installation
and an authored source. See the [Blender glTF exporter API](https://docs.blender.org/api/current/bpy.ops.export_scene.html).

## Asset handoff to the artist

Supply a golden eagle (*Aquila chrysaetos*), with an anatomically proportioned
body, natural amber-brown eyes, curved beak, feathered legs, articulated talons,
layered golden/dark-brown plumage, separate wing feather controls and tail fans.
No white bald-eagle head, oversized eyes, cartoon shape, or low-poly substitute.
Use wildlife references and review side/front/back views and motion at slow speed.

Create a clean `.blend` with an `Eagle` collection containing one armature and
its meshes. Use metres, rig origin at ground between the feet, applied object
transforms, Blender +Z up and -Y forward (glTF export becomes +Y up, +Z forward).
Aim for about 0.8–1 m standing height and a 1.8–2.3 m wingspan. Keep flight in place;
Landing should descend only enough to fit the dashboard camera. The app camera
looks at y=0.5 m from 3.4 m away. Reframe against the final model, including full
wing extension, before approving it.

Required deform/control bone names are in [asset_contract.json](asset_contract.json).
Recommended hierarchy:

- `Root` → `Body` → `Spine` → `Neck` → `Head` → `Beak`, `Eye.L`, `Eye.R`.
- `Spine` → `Shoulder.L` → `WingUpper.L` → `WingMiddle.L` → `WingFeathers.L`;
  mirror the chain with `.R` names.
- `Body` → `Tail`, `Leg.L`, `Leg.R`; add individually articulated toes and talons.
- Add eyelid bones or shape keys, primary/secondary feather fans, and tail controls.

Bake constraints and corrective motion to exported bones/morphs; validate feather
overlap throughout the folded and extended poses. Use at most four normalized
weights per vertex. Bone parenting is allowed for rigid eyes/beak details. Keep
exactly the eight authored actions described in
[ANIMATIONS.md](../../documentation/eagle/ANIMATIONS.md). Each must be independently
playable and contain different motion. Names alone do not establish animation quality.

Use exportable Principled BSDF PBR materials, real base-color, normal, and packed
metallic-roughness textures. Color maps are sRGB; normal/roughness maps are non-color.
Bake procedural/hair materials and feather cards before export. Review alpha edges
and depth sorting in Flutter Scene. Thin feather cards can use masked alpha and
double-sided materials where required. Do not apply double-sided shading indiscriminately.

Initial budgets: ≤100,000 triangles, ≤30 MiB GLB, ≤2048 px texture edges and ≤128 MiB
estimated RGBA texture storage including mipmaps. These are intake limits, not
measured performance guarantees. Start lower for mid-range phones. No Draco,
meshopt or KTX2 compression until tested against the pinned renderer.

## Export without replacing source files

Copy `license.example.json` outside the app assets and fill it with the real asset
provenance, attribution and licence permissions. Keep purchase receipts separately.
The exporter verifies filled fields; it cannot establish legal ownership for you.

From the repository root:

```sh
/Applications/Blender.app/Contents/MacOS/Blender \
  --background --disable-autoexec \
  --python tools/eagle/export_eagle.py -- \
  --source /absolute/path/to/approved_golden_eagle.blend \
  --license /absolute/path/to/license.json \
  --output tools/eagle/output/review-001
```

Output must be a new directory. The source is opened without running embedded
scripts and is never saved over. A failed export leaves a staging directory for
inspection. A successful structural validation produces:

- `eagle_mascot.glb`, embedded PNG/JPEG textures and eight named clips.
- `eagle_mascot.blend`, a copy of the source with packed images.
- `textures/`, the actual embedded texture files extracted from the GLB.
- `CREDITS.md`, `license.json`, `validation.json`.

No geometry, rig or animation authoring is performed by the exporter. Those are
artist deliverables; it fails when they are missing. Exporter flags are based on
the documented API and still require execution against the selected Blender build.

## Validate and integrate

```sh
python3 tools/eagle/validate_glb.py tools/eagle/output/review-001/eagle_mascot.glb
python3 -B -m unittest discover -s tools/eagle -p 'test_*.py' -v
```

The validator checks GLB chunk bounds, embedded resources, unique node names,
hierarchy, required skin joints, weights, nondegenerate triangles, normals, UVs,
PBR texture references, budgets, distinct animated channels, and clip names/times.
It deliberately does **not** certify photorealism, texture pixel decoding,
anatomy, all glTF rules or Android playback. Also run the official
[Khronos glTF Validator](https://github.com/KhronosGroup/glTF-Validator) and inspect
every clip in Blender and on the phone. Python test fixtures are tiny synthetic
triangles only, never production assets.

After visual and licence review, install without overwriting existing assets:

```sh
python3 tools/eagle/install_asset.py tools/eagle/output/review-001
cd apps/eagle-study-android
flutter pub get
flutter analyze
flutter test
flutter run --enable-flutter-gpu
```

The installer copies the GLB and attribution into `assets/3d/`. The generated
build hook converts the GLB at build time; `loadScene` loads its compiled form.
Credit text is registered on Flutter's licence page when the eagle view is used.
The old bald-eagle credits and native implementation were preserved with the
pre-existing work; they are not the source for this golden-eagle feature.

## Flutter integration

Pinned [Flutter Scene 0.24.6](https://pub.dev/packages/flutter_scene/versions/0.24.6)
requires Flutter ≥3.47 and supports Android. API use was checked against the exact
package source: `SceneView`, `loadScene`, `releaseScene`, `createAnimationClip`,
`AnimationClip.playbackTime`, `Scene.update`, `Scene.dispose`. Android's manifest
enables Flutter GPU. The new files live under `lib/features/eagle/`; only the
dashboard call site is switched away from the legacy native eagle.

`EagleAnimationController.play(type, loop: ...)` selects any clip. The renderer
crossfades weights over 250 ms, uses imported durations, and reports completion
with a request ID so a stale callback cannot interrupt a newer animation. All
one-shots return to Idle. Start/resume triggers Study_Start, pause/break triggers
Rest, saving a session (including goal completion) triggers Celebrate. Wake_Up is
the initial request once per app provider lifetime.

The dashboard has a persistent `3D eagle` switch backed by the existing SQLite
`app_state` table. Unsupported devices, missing assets, reduced motion and renderer
errors use a static landscape icon, which is a temporary fallback, not eagle art.
The existing Android low-RAM/GLES check is only a conservative first gate;
Flutter GPU initialization and rendering failures are caught separately.

Backgrounding or hiding the route disposes the scene and releases its model cache
claim; returning reloads the current requested clip from its beginning. Rendering
is capped at 60 Hz, resolution at 2× logical size, with adaptive medium quality.
No continuous rendering runs for the fallback. A visible eagle still renders each
frame; scroll visibility and actual device memory/thermal behavior need profiling.

To isolate renderer setup before adding the model:

```sh
flutter run -t lib/eagle_scene_probe.dart --enable-flutter-gpu
```

This diagnostic is a PBR cube, clearly labelled as a rendering probe. It is not
shipped as a replacement eagle. It builds for Android, but on-device rendering
has not been observed here. Rebuild with `-t lib/main.dart` for the study app.

No Go API change is needed: animation and the rendering preference are local UI
state, and existing session persistence remains authoritative.
