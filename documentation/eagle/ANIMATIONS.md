# Golden-eagle animation contract

These are requirements for the forthcoming model, not a claim that animation
artwork has been delivered. Names are case-sensitive. Start every exported clip
at 0 seconds; bake constraints to skeleton or morph channels. Suggested lengths
are artistic guidance only; the application reads the actual imported duration.

| Dart value | glTF clip | Default | Suggested length | Required motion |
| --- | --- | --- | --- | --- |
| idle | Idle | Loop | 6–10 s | Breathing, subtle gaze shifts, blink, slight feather motion; continuous seam. |
| studyStart | Study_Start | Once → Idle | 2–3 s | Rise, open both wings with anatomical articulation, natural hold, return to an idle-compatible pose. |
| wingFlap | Wing_Flap | Loop | 1–2 s | Shoulder-led downstroke, folded recovery, delayed feather flex; no whole-body spinning. |
| fly | Fly | Loop | 1.5–3 s | In-place flight cycle with tucked feet, body and tail stabilization; distinct from grounded Wing_Flap. |
| landing | Landing | Once → Idle | 2–4 s | Braking extension, controlled short descent, feet reach/contact, fold and settle. |
| celebrate | Celebrate | Once → Idle | 2–4 s | Powerful wing spread, natural head turn and brief proud stance, settle. |
| rest | Rest | Loop | 6–10 s | Relaxed folded wings, slow breathing, lowered head; distinct from alert Idle. |
| wakeUp | Wake_Up | Once → Idle | 2–3 s | Eyelids open, head rises, posture becomes alert, settle into Idle. |

Keep both endpoints continuous for loops, with matching pose and velocity.
For one-shots, finish near the Idle pose so the 250 ms blend is natural. Bake
feather controls and eyelid morphs, not only armature-object transforms. Do not
share identical keyframe data under different action names. The validator catches
exact duplicates and static actions; only visual review can judge meaningful
differences, believable wing anatomy, foot sliding and mesh intersections.

App events use the same controller whether or not 3D is currently enabled.
Completion comes from playback progress, so time spent backgrounded does not
prematurely finish a clip. Remounting a disposed renderer restarts its current
request; it does not issue another Wake_Up request. Call
`ref.read(eagleAnimationProvider.notifier).beginBreak()` from any future explicit
break scheduler. In the current app, pausing a study session is the break event.

Verification per clip: solo it, scrub frame by frame, play it at 1× speed, test
crossfades in both directions with Idle, verify feather/skin continuity and shadow
edges, and measure camera bounds at full wing spread. Then repeat playback on
an Android device. There are currently no clips available to perform this QA.
