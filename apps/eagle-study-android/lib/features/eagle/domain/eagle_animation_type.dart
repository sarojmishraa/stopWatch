/// Stable names shared by Blender, glTF and the application.
enum EagleAnimationType {
  idle('Idle', true),
  studyStart('Study_Start', false),
  wingFlap('Wing_Flap', true),
  fly('Fly', true),
  landing('Landing', false),
  celebrate('Celebrate', false),
  rest('Rest', true),
  wakeUp('Wake_Up', false);

  const EagleAnimationType(this.clipName, this.loops);
  final String clipName;
  final bool loops;
}
