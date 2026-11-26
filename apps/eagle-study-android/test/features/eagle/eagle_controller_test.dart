import 'package:eagle_study/features/eagle/application/eagle_controller.dart';
import 'package:eagle_study/features/timer/application/study_timer_controller.dart';
import 'package:eagle_study/features/timer/domain/study_timer_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_env.dart';

void main() {
  test('mood follows the session: idle → focus → rest', () {
    expect(moodFor(const StudyTimerState()), EagleMood.idle);
    expect(
      moodFor(const StudyTimerState(isRunning: true, sessionId: 's')),
      EagleMood.focus,
    );
    expect(moodFor(const StudyTimerState(sessionId: 's')), EagleMood.rest);
  });

  test(
    'the eagle reacts to start, pause, and celebrates a saved session',
    () async {
      final env = await TestEnv.create();
      final c = env.container();
      final timer = c.read(studyTimerProvider.notifier);
      await timer.ready;
      c.listen(
        eagleMoodProvider,
        (_, _) {},
      ); // keep it alive like a widget would

      expect(c.read(eagleMoodProvider), EagleMood.idle);
      timer.startOrResume();
      expect(c.read(eagleMoodProvider), EagleMood.focus);
      env.clock.advance(const Duration(minutes: 20));
      timer.pause();
      expect(c.read(eagleMoodProvider), EagleMood.rest);

      await timer.finish();
      expect(c.read(eagleMoodProvider), EagleMood.celebrate);

      await Future<void>.delayed(
        EagleMoodController.celebrationLength +
            const Duration(milliseconds: 100),
      );
      expect(c.read(eagleMoodProvider), EagleMood.idle);
    },
  );
}
