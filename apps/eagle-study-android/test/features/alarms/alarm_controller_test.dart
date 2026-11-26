import 'package:eagle_study/features/alarms/application/alarm_controller.dart';
import 'package:eagle_study/features/alarms/data/alarm_repository.dart';
import 'package:eagle_study/features/alarms/domain/alarm.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_env.dart';

void main() {
  late TestEnv env;
  late ProviderContainer c;

  setUp(() async {
    env = await TestEnv.create();
    c = env.container();
    await c.read(alarmControllerProvider.future);
  });

  AlarmController controller() => c.read(alarmControllerProvider.notifier);

  test('saving stores the alarm and schedules it natively', () async {
    await controller().save(
      const Alarm(id: 'morning', hour: 7, minute: 0, days: {1, 2, 3, 4, 5}),
    );

    expect(c.read(alarmControllerProvider).value!.single.id, 'morning');
    expect(env.alarms.synced.single['id'], 'morning');
    expect(env.alarms.synced.single['zone'], 'Asia/Kolkata');
    // Persisted: a fresh read from SQLite sees it.
    expect((await AlarmRepository(env.database).all()).single.days, {
      1,
      2,
      3,
      4,
      5,
    });
  });

  test('disabled alarms are removed from the native schedule', () async {
    await controller().save(const Alarm(id: 'a', hour: 7, minute: 0));
    await controller().save(const Alarm(id: 'b', hour: 8, minute: 0));
    await controller().setEnabled('a', false);

    expect(env.alarms.synced.map((m) => m['id']), ['b']);
    final stored = c.read(alarmControllerProvider).value!;
    expect(stored.firstWhere((a) => a.id == 'a').enabled, isFalse);
  });

  test('delete unschedules and removes the recording file', () async {
    await controller().save(
      const Alarm(
        id: 'r',
        hour: 6,
        minute: 0,
        sound: AlarmSound.recording,
        recordingPath: '/rec/r.m4a',
      ),
    );
    await controller().delete('r');

    expect(c.read(alarmControllerProvider).value, isEmpty);
    expect(env.alarms.synced, isEmpty);
    await Future<void>.delayed(Duration.zero);
    expect(env.alarms.calls, contains('delete:/rec/r.m4a'));
  });

  test(
    'one-time alarms that rang while the app was closed are turned off',
    () async {
      await controller().save(const Alarm(id: 'once', hour: 6, minute: 0));
      env.alarms.firedOneShots = ['once'];

      await controller().refreshFired();

      expect(c.read(alarmControllerProvider).value!.single.enabled, isFalse);
    },
  );

  test('invalid alarms are rejected and nothing is scheduled', () async {
    final syncsBefore = env.alarms.syncCalls;
    await expectLater(
      controller().save(
        const Alarm(id: 'x', hour: 7, minute: 0, sound: AlarmSound.recording),
      ),
      throwsA(isA<InvalidAlarmException>()),
    );
    expect(env.alarms.syncCalls, syncsBefore);
    expect(c.read(alarmControllerProvider).value, isEmpty);
  });

  test('next alarm is the earliest enabled one', () async {
    await controller().save(const Alarm(id: 'late', hour: 21, minute: 0));
    await controller().save(const Alarm(id: 'soon', hour: 11, minute: 0));
    await controller().save(
      const Alarm(id: 'off', hour: 10, minute: 30, enabled: false),
    );

    final next = c.read(nextAlarmProvider)!;
    expect(next.alarm.id, 'soon');
    expect(next.at.toUtc(), DateTime.utc(2026, 12, 1, 5, 30));
  });

  test(
    'timer end sound is stored; recordings are not allowed for it',
    () async {
      final repo = AlarmRepository(env.database);
      expect(await repo.timerSound(), AlarmSound.classic);
      await repo.setTimerSound(AlarmSound.ghost);
      expect(await repo.timerSound(), AlarmSound.ghost);
      await expectLater(
        repo.setTimerSound(AlarmSound.recording),
        throwsA(isA<InvalidAlarmException>()),
      );
    },
  );
}
