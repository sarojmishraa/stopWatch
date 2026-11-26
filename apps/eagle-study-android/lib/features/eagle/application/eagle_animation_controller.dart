import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../timer/application/study_timer_controller.dart';
import '../domain/eagle_animation_type.dart';
import 'eagle_animation_state.dart';

final eagleAnimationProvider =
    NotifierProvider<EagleAnimationController, EagleAnimationState>(
      EagleAnimationController.new,
    );

/// Owns intent; the renderer reports actual clip completion. No guessed timers.
/// Kept alive for the app's ProviderScope, so Wake_Up runs once per launch.
class EagleAnimationController extends Notifier<EagleAnimationState> {
  @override
  EagleAnimationState build() {
    ref.listen(studyTimerProvider, (previous, next) {
      if (next.lastSaved != null &&
          next.lastSaved?.sessionId != previous?.lastSaved?.sessionId) {
        play(EagleAnimationType.celebrate);
      } else if (next.isRunning && previous?.isRunning != true) {
        play(EagleAnimationType.studyStart);
      } else if (!next.isRunning &&
          next.hasSession &&
          (previous?.isRunning == true || previous?.hasSession != true)) {
        beginBreak();
      } else if (!next.hasSession && previous?.hasSession == true) {
        play(EagleAnimationType.idle);
      }
    });
    return const EagleAnimationState();
  }

  void play(EagleAnimationType animation, {bool? loop}) {
    state = EagleAnimationState(
      animation: animation,
      loop: loop ?? animation.loops,
      requestId: state.requestId + 1,
    );
  }

  /// Timer pause is the current app's break action. A future break scheduler
  /// can call this same method without coupling to the renderer.
  void beginBreak() => play(EagleAnimationType.rest);

  /// Ignore stale completions after a new clip superseded the old request.
  void completed(int requestId) {
    if (state.requestId != requestId || state.loop) return;
    play(EagleAnimationType.idle);
  }
}
