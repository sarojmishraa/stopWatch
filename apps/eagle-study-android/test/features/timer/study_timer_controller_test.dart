import 'package:eagle_study/features/alarms/data/alarm_repository.dart';
import 'package:eagle_study/features/alarms/domain/alarm.dart';
import 'package:eagle_study/features/sessions/domain/study_session.dart';
import 'package:eagle_study/features/timer/application/study_timer_controller.dart';
import 'package:eagle_study/features/timer/domain/study_timer_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_env.dart';

void main() {
  late TestEnv env;

  setUp(() async => env = await TestEnv.create());

  Future<StudyTimerController> controllerOf(ProviderContainer c) async {
    final controller = c.read(studyTimerProvider.notifier);
    await controller.ready;
    return controller;
  }

  Future<List<StudySessionRecord>> saved() => env.repository.history();

  test(
    'stopwatch: pauses are excluded, laps and real end time are kept',
    () async {
      final c = env.container();
      final timer = await controllerOf(c);
      final t0 = env.clock.now;

      timer.setSubject('Java');
      timer.startOrResume();
      env.clock.advance(const Duration(minutes: 10));
      timer.pause();
      env.clock.advance(const Duration(minutes: 5)); // break: not counted
      timer.startOrResume();
      env.clock.advance(const Duration(minutes: 20));
      expect(timer.addLap(), isTrue);
      env.clock.advance(const Duration(minutes: 1));

      expect(await timer.finish(), FinishOutcome.saved);

      final s = (await saved()).single;
      expect(s.mode, SessionMode.stopwatch);
      expect(s.durationSeconds, 31 * 60);
      expect(s.startedAt, t0);
      expect(s.endedAt, t0.add(const Duration(minutes: 36)));
      expect(s.lapsSeconds, [30 * 60]);
      expect(s.subject, 'Java');
      expect(c.read(studyTimerProvider).hasSession, isFalse);
      expect(
        c.read(studyTimerProvider).subject,
        'Java',
        reason: 'kept for next session',
      );
      expect(c.read(studyTimerProvider).lastSaved?.durationSeconds, 31 * 60);
    },
  );

  test('countdown that ended while the app was suspended is saved with '
      'its real end time', () async {
    final c = env.container();
    final timer = await controllerOf(c);
    final t0 = env.clock.now;

    expect(timer.setCountdownDuration(25 * 60), isTrue);
    timer.startOrResume();
    env.clock.advance(const Duration(minutes: 40)); // app was in background
    await timer.checkCountdown(); // what onResume does

    final s = (await saved()).single;
    expect(s.mode, SessionMode.countdown);
    expect(s.durationSeconds, 1500);
    expect(s.plannedSeconds, 1500);
    expect(s.endedAt, t0.add(const Duration(minutes: 25)));
    final state = c.read(studyTimerProvider);
    expect(state.mode, TimerMode.countdown);
    expect(state.accumulatedSeconds, 1500, reason: 'ready for the next one');
  });

  test('finishing a paused countdown early saves only the focused part, '
      'ending when it was paused', () async {
    final c = env.container();
    final timer = await controllerOf(c);
    final t0 = env.clock.now;

    timer.setCountdownDuration(25 * 60);
    timer.startOrResume();
    env.clock.advance(const Duration(minutes: 10));
    timer.pause();
    env.clock.advance(const Duration(hours: 2));

    expect(await timer.finish(), FinishOutcome.saved);
    final s = (await saved()).single;
    expect(s.durationSeconds, 600);
    expect(s.endedAt, t0.add(const Duration(minutes: 10)));
  });

  test('a running session survives the process being killed', () async {
    var c = env.container();
    var timer = await controllerOf(c);
    timer.setSubject('Go');
    timer.startOrResume();
    final sessionId = c.read(studyTimerProvider).sessionId;
    env.clock.advance(const Duration(minutes: 5));
    timer.addLap();
    await env.database.loadTimerState(); // flush queued writes
    c.dispose();

    await env.restartProcess();
    env.clock.advance(const Duration(minutes: 5));
    c = env.container();
    timer = await controllerOf(c);

    final state = c.read(studyTimerProvider);
    expect(state.isRunning, isTrue);
    expect(state.sessionId, sessionId);
    expect(state.laps, [300]);
    expect(state.secondsAt(env.clock.now.millisecondsSinceEpoch), 600);

    await timer.finish();
    final s = (await saved()).single;
    expect(s.id, sessionId);
    expect(s.durationSeconds, 600);
    expect(s.subject, 'Go');
  });

  test('finishing twice at once saves exactly one session', () async {
    final c = env.container();
    final timer = await controllerOf(c);
    timer.startOrResume();
    env.clock.advance(const Duration(minutes: 3));

    final outcomes = await Future.wait([timer.finish(), timer.finish()]);

    expect(outcomes, contains(FinishOutcome.saved));
    expect(await env.count('study_sessions'), 1);
  });

  test('under one second is discarded, not saved', () async {
    final c = env.container();
    final timer = await controllerOf(c);
    timer.startOrResume();
    env.clock.advance(const Duration(milliseconds: 600));

    expect(await timer.finish(), FinishOutcome.tooShort);
    expect(await env.count('study_sessions'), 0);
    expect(c.read(studyTimerProvider).hasSession, isFalse);
  });

  test(
    'a stopwatch left running for over a day is capped at 24 hours',
    () async {
      final c = env.container();
      final timer = await controllerOf(c);
      timer.startOrResume();
      env.clock.advance(const Duration(hours: 30));

      expect(await timer.finish(), FinishOutcome.savedCapped);
      expect((await saved()).single.durationSeconds, maxSessionSeconds);
    },
  );

  test('reset discards the session and nothing is saved', () async {
    final c = env.container();
    final timer = await controllerOf(c);
    timer.startOrResume();
    env.clock.advance(const Duration(minutes: 30));

    await timer.reset();

    expect(await env.count('study_sessions'), 0);
    expect(c.read(studyTimerProvider).hasSession, isFalse);
  });

  test(
    'guards: duration limits, no mode change mid-session, lap limit',
    () async {
      final c = env.container();
      final timer = await controllerOf(c);
      expect(timer.setCountdownDuration(0), isFalse);
      expect(timer.setCountdownDuration(maxSessionSeconds + 1), isFalse);

      timer.startOrResume();
      timer.selectMode(TimerMode.countdown);
      expect(c.read(studyTimerProvider).mode, TimerMode.stopwatch);
      expect(timer.setCountdownDuration(600), isFalse);

      for (var i = 0; i < maxLaps; i++) {
        env.clock.advance(const Duration(seconds: 1));
        expect(timer.addLap(), isTrue);
      }
      expect(timer.addLap(), isFalse);
      await env.database.loadTimerState(); // let queued writes finish
    },
  );

  group('focus timer completion alarm', () {
    Future<void> flush() =>
        Future<void>.delayed(const Duration(milliseconds: 50));

    test('starting a countdown schedules a native alarm at its end, using '
        'the chosen sound and subject', () async {
      await AlarmRepository(env.database).setTimerSound(AlarmSound.ghost);
      final c = env.container();
      final timer = await controllerOf(c);
      final t0 = env.clock.now;

      timer.setSubject('DSA');
      timer.setCountdownDuration(25 * 60);
      timer.startOrResume();
      await flush();

      final armed = env.alarms.timerEnd!;
      expect(armed.at, t0.add(const Duration(minutes: 25)));
      expect(armed.sound, 'ghost');
      expect(armed.message, contains('DSA'));
    });

    test('pause cancels it and resume re-arms it for the new end', () async {
      final c = env.container();
      final timer = await controllerOf(c);
      final t0 = env.clock.now;
      timer.setCountdownDuration(25 * 60);
      timer.startOrResume();
      env.clock.advance(const Duration(minutes: 10));
      timer.pause();
      await flush();
      expect(env.alarms.timerEnd, isNull);

      env.clock.advance(const Duration(minutes: 5));
      timer.startOrResume();
      await flush();
      expect(env.alarms.timerEnd!.at, t0.add(const Duration(minutes: 30)));
    });

    test('natural completion keeps the alarm (it is the completion sound); '
        'finishing early cancels it', () async {
      final c = env.container();
      final timer = await controllerOf(c);
      timer.setCountdownDuration(60);
      timer.startOrResume();
      await flush();
      env.clock.advance(const Duration(minutes: 2));
      final cancelsBefore = env.alarms.timerCancels;
      await timer.checkCountdown();
      expect(env.alarms.timerCancels, cancelsBefore);

      timer.startOrResume();
      env.clock.advance(const Duration(seconds: 20));
      await timer.finish();
      await flush();
      expect(env.alarms.timerEnd, isNull);
    });

    test('stopwatch sessions never schedule a timer alarm', () async {
      final c = env.container();
      final timer = await controllerOf(c);
      timer.startOrResume();
      await flush();
      expect(env.alarms.timerEnd, isNull);
    });
  });
}
