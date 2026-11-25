import 'package:flutter_test/flutter_test.dart';
import 'package:eagle_study/features/timer/domain/study_timer_state.dart';

void main() {
  group('StudyTimerState.secondsAt', () {
    test('calculates stopwatch elapsed time from its timestamp anchor', () {
      const state = StudyTimerState(
        isRunning: true,
        accumulatedSeconds: 12,
        segmentStartedAtMs: 10000,
      );

      expect(state.secondsAt(18500), 20);
    });

    test('returns paused stopwatch time without advancing', () {
      const state = StudyTimerState(accumulatedSeconds: 73);

      expect(state.secondsAt(999999), 73);
    });

    test('counts a countdown down from its absolute end time', () {
      const state = StudyTimerState(
        mode: TimerMode.countdown,
        isRunning: true,
        accumulatedSeconds: 1500,
        countdownEndAtMs: 160000,
        countdownDurationSeconds: 1500,
      );

      expect(state.secondsAt(41500), 119);
      expect(state.secondsAt(161000), 0);
    });
  });
}
