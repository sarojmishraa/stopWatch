import 'package:eagle_study/features/eagle/application/eagle_animation_controller.dart';
import 'package:eagle_study/features/eagle/application/eagle_render_settings.dart';
import 'package:eagle_study/features/eagle/domain/eagle_animation_type.dart';
import 'package:eagle_study/features/timer/application/study_timer_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_env.dart';

void main() {
  test(
    'wake once, start, break, save, and complete use real requests',
    () async {
      final env = await TestEnv.create();
      final container = env.container();
      final timer = container.read(studyTimerProvider.notifier);
      await timer.ready;
      final subscription = container.listen(eagleAnimationProvider, (_, _) {});
      addTearDown(subscription.close);
      final eagle = container.read(eagleAnimationProvider.notifier);
      expect(
        container.read(eagleAnimationProvider).animation,
        EagleAnimationType.wakeUp,
      );
      eagle.completed(0);
      expect(
        container.read(eagleAnimationProvider).animation,
        EagleAnimationType.idle,
      );

      timer.startOrResume();
      final started = container.read(eagleAnimationProvider);
      expect(started.animation, EagleAnimationType.studyStart);
      env.clock.advance(const Duration(minutes: 2));
      timer.pause();
      expect(
        container.read(eagleAnimationProvider).animation,
        EagleAnimationType.rest,
      );
      eagle.completed(
        started.requestId,
      ); // late completion cannot override break
      expect(
        container.read(eagleAnimationProvider).animation,
        EagleAnimationType.rest,
      );

      await timer.finish();
      final celebration = container.read(eagleAnimationProvider);
      expect(celebration.animation, EagleAnimationType.celebrate);
      eagle.completed(celebration.requestId);
      expect(
        container.read(eagleAnimationProvider).animation,
        EagleAnimationType.idle,
      );
      subscription.close();
      final again = container.listen(eagleAnimationProvider, (_, _) {});
      addTearDown(again.close);
      expect(
        container.read(eagleAnimationProvider).animation,
        EagleAnimationType.idle,
      );
    },
  );

  test('every clip supports replay and explicit loop control', () async {
    final env = await TestEnv.create();
    final container = env.container();
    await container.read(studyTimerProvider.notifier).ready;
    final eagle = container.read(eagleAnimationProvider.notifier);
    for (final type in EagleAnimationType.values) {
      eagle.play(type, loop: false);
      final first = container.read(eagleAnimationProvider);
      expect(first.animation, type);
      eagle.play(type, loop: false);
      final replay = container.read(eagleAnimationProvider);
      expect(replay.requestId, greaterThan(first.requestId));
      eagle.completed(first.requestId);
      expect(
        container.read(eagleAnimationProvider).requestId,
        replay.requestId,
      );
      eagle.completed(replay.requestId);
      expect(
        container.read(eagleAnimationProvider).animation,
        EagleAnimationType.idle,
      );
      eagle.play(type, loop: true);
      final loop = container.read(eagleAnimationProvider);
      eagle.completed(loop.requestId);
      expect(container.read(eagleAnimationProvider).requestId, loop.requestId);
    }
  });

  test(
    '3D preference survives reopening the database and rapid toggles',
    () async {
      final env = await TestEnv.create();
      final container = env.container();
      expect(await container.read(eagleRenderEnabledProvider.future), isTrue);
      final settings = container.read(eagleRenderEnabledProvider.notifier);
      await Future.wait([
        settings.setEnabled(false),
        settings.setEnabled(true),
        settings.setEnabled(false),
      ]);
      expect(container.read(eagleRenderEnabledProvider).value, isFalse);
      await env.restartProcess();
      final restarted = env.container();
      expect(await restarted.read(eagleRenderEnabledProvider.future), isFalse);
    },
  );
}
