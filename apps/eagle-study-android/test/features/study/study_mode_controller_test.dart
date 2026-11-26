import 'package:eagle_study/features/study/application/study_mode_controller.dart';
import 'package:eagle_study/features/study/domain/study_mode_prefs.dart';
import 'package:eagle_study/features/timer/application/study_timer_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_env.dart';

void main() {
  late TestEnv env;

  setUp(() async => env = await TestEnv.create());

  Future<void> flush() =>
      Future<void>.delayed(const Duration(milliseconds: 30));

  Future<void> setPrefs(ProviderContainer c, StudyModePrefs prefs) async {
    await c.read(studyModePrefsProvider.future);
    await c.read(studyModePrefsProvider.notifier).save(prefs);
  }

  group('Study Mode', () {
    test('keeps the screen on while open and releases it on exit; DND off '
        'by default', () async {
      final c = env.container();
      final mode = c.read(studyModeProvider.notifier);

      await mode.enter();
      expect(env.studyMode.keepScreenOn, isTrue);
      expect(
        env.studyMode.calls.where((c) => c.startsWith('enterDnd')),
        isEmpty,
      );

      await mode.exit();
      expect(env.studyMode.keepScreenOn, isFalse);
      expect(c.read(studyModeProvider).active, isFalse);
    });

    test(
      'with access, applies the chosen DND mode and restores on exit',
      () async {
        env.studyMode.access = true;
        final c = env.container();
        await setPrefs(c, const StudyModePrefs(dnd: DndMode.alarms));
        final mode = c.read(studyModeProvider.notifier);

        await mode.enter();
        expect(env.studyMode.calls, contains('enterDnd:alarms'));
        expect(c.read(studyModeProvider).dndApplied, isTrue);
        expect(env.studyMode.dndOn, isTrue);

        await mode.exit();
        expect(
          env.studyMode.dndOn,
          isFalse,
          reason: 'previous setting restored',
        );
      },
    );

    test(
      'without access, DND is not changed and the user is told why',
      () async {
        final c = env.container();
        await setPrefs(c, const StudyModePrefs(dnd: DndMode.priority));

        await c.read(studyModeProvider.notifier).enter();

        expect(env.studyMode.dndOn, isFalse);
        expect(c.read(studyModeProvider).dndApplied, isFalse);
        expect(c.read(studyModeProvider).notice, contains('allow access'));
      },
    );

    test('changing settings while open re-applies them', () async {
      env.studyMode.access = true;
      final c = env.container();
      await c.read(studyModeProvider.notifier).enter();
      expect(env.studyMode.dndOn, isFalse);

      await setPrefs(
        c,
        const StudyModePrefs(dnd: DndMode.alarms, keepScreenOn: false),
      );
      expect(env.studyMode.dndOn, isTrue);
      expect(env.studyMode.keepScreenOn, isFalse);

      await setPrefs(c, const StudyModePrefs());
      expect(env.studyMode.dndOn, isFalse);
    });

    test('settings persist across restarts', () async {
      var c = env.container();
      await setPrefs(
        c,
        const StudyModePrefs(dnd: DndMode.alarms, sessionNotification: false),
      );
      c.dispose();
      c = env.container();
      final prefs = await c.read(studyModePrefsProvider.future);
      expect(prefs.dnd, DndMode.alarms);
      expect(prefs.sessionNotification, isFalse);
    });

    test(
      'after a crash in Study Mode, DND is restored on next start',
      () async {
        env.studyMode.dndOn = true; // left on by a killed process
        final c = env.container();
        await c.read(studyModeProvider.notifier).healAfterRestart();
        expect(env.studyMode.dndOn, isFalse);
      },
    );
  });

  group('session notification', () {
    test(
      'follows the timer: shown while running/paused, removed when done',
      () async {
        final c = env.container();
        c.read(sessionNotificationSyncProvider);
        final timer = c.read(studyTimerProvider.notifier);
        await timer.ready;

        timer.setSubject('Go');
        timer.startOrResume();
        await flush();
        expect(env.studyMode.notification?['isRunning'], isTrue);
        expect(env.studyMode.notification?['subject'], 'Go');

        env.clock.advance(const Duration(minutes: 5));
        timer.pause();
        await flush();
        expect(env.studyMode.notification?['isRunning'], isFalse);

        await timer.finish();
        await flush();
        expect(env.studyMode.notification, isNull);
      },
    );

    test('is not shown when turned off in settings', () async {
      final c = env.container();
      await setPrefs(c, const StudyModePrefs(sessionNotification: false));
      c.read(sessionNotificationSyncProvider);
      final timer = c.read(studyTimerProvider.notifier);
      await timer.ready;
      timer.startOrResume();
      await flush();
      expect(env.studyMode.notification, isNull);
    });

    test('Pause, Resume and Finish buttons drive the timer', () async {
      final c = env.container();
      var finishedCallback = 0;
      c.read(studyNotificationActionsProvider).onFinished = () =>
          finishedCallback++;
      final timer = c.read(studyTimerProvider.notifier);
      await timer.ready;
      timer.startOrResume();
      env.clock.advance(const Duration(minutes: 3));

      env.studyMode.actionHandler!('pause');
      await flush();
      expect(c.read(studyTimerProvider).isRunning, isFalse);

      env.studyMode.actionHandler!('resume');
      await flush();
      expect(c.read(studyTimerProvider).isRunning, isTrue);

      // Finish arrives as a pending action because it opens the app.
      env.studyMode.pendingAction = 'finish';
      await c.read(studyNotificationActionsProvider).handlePending();
      expect(c.read(studyTimerProvider).hasSession, isFalse);
      expect(await env.count('study_sessions'), 1);
      expect(finishedCallback, 1);
    });
  });
}
