import '../domain/eagle_animation_type.dart';

class EagleAnimationState {
  const EagleAnimationState({
    this.animation = EagleAnimationType.wakeUp,
    this.loop = false,
    this.requestId = 0,
  });

  final EagleAnimationType animation;
  final bool loop;

  /// Distinguishes a replay from the previous invocation of the same clip.
  final int requestId;
}
