import 'package:eagle_study/core/time/study_calendar.dart';
import 'package:eagle_study/features/alarms/domain/alarm.dart';
import 'package:eagle_study/features/alarms/presentation/alarm_format.dart';
import 'package:flutter_test/flutter_test.dart';

/// Same cases as android/app/src/test/.../NextTriggerTest.kt.
void main() {
  final kolkata = StudyCalendar.kolkata();
  final now = DateTime.utc(2026, 12, 1, 4, 30); // Tue 1 Dec 10:00 IST

  Alarm alarm(int hour, int minute, [Set<int> days = const {}]) =>
      Alarm(id: 'a', hour: hour, minute: minute, days: days);

  DateTime next(Alarm a, [StudyCalendar? calendar]) =>
      nextTrigger(a, now, calendar ?? kolkata).toUtc();

  test('one-time alarm later today', () {
    expect(next(alarm(11, 0)), DateTime.utc(2026, 12, 1, 5, 30));
  });

  test('one-time alarm for an earlier time rings tomorrow', () {
    expect(next(alarm(9, 0)), DateTime.utc(2026, 12, 2, 3, 30));
  });

  test('exactly now is not now', () {
    expect(next(alarm(10, 0)), DateTime.utc(2026, 12, 2, 4, 30));
  });

  test('weekdays skip to Wednesday; weekends wait for Saturday', () {
    expect(
      next(alarm(7, 0, {1, 2, 3, 4, 5})),
      DateTime.utc(2026, 12, 2, 1, 30),
    );
    expect(next(alarm(7, 0, {6, 7})), DateTime.utc(2026, 12, 5, 1, 30));
  });

  test('same weekday already passed rings next week', () {
    expect(next(alarm(10, 0, {2})), DateTime.utc(2026, 12, 8, 4, 30));
  });

  test('other zones use their own clock', () {
    expect(
      next(alarm(7, 0), StudyCalendar('Europe/Berlin')),
      DateTime.utc(2026, 12, 1, 6),
    );
  });

  test('validation', () {
    expect(alarm(7, 0).validate(), isEmpty);
    expect(alarm(24, 0).validate(), isNotEmpty);
    expect(alarm(7, 0, {0}).validate(), isNotEmpty);
    expect(alarm(7, 0).copyWith(volume: 0).validate(), isNotEmpty);
    expect(alarm(7, 0).copyWith(message: 'x' * 201).validate(), isNotEmpty);
    expect(
      alarm(7, 0).copyWith(sound: AlarmSound.recording).validate(),
      contains('Record your voice first, or pick another sound.'),
    );
  });

  test('native payload matches AlarmSpec.fromMap', () {
    final payload = alarm(
      6,
      45,
      {5, 1, 3},
    ).copyWith(sound: AlarmSound.ghost, message: '  ').toNative('Asia/Kolkata');
    expect(payload, {
      'id': 'a',
      'hour': 6,
      'minute': 45,
      'days': [1, 3, 5],
      'message': 'Time to study. Wake up, eagle.',
      'sound': 'ghost',
      'volume': 0.8,
      'vibrate': true,
      'recordingPath': null,
      'zone': 'Asia/Kolkata',
    });
  });

  test('labels', () {
    expect(repeatLabel({}), 'Once');
    expect(repeatLabel({1, 2, 3, 4, 5}), 'Weekdays');
    expect(repeatLabel({6, 7}), 'Weekends');
    expect(repeatLabel({1, 2, 3, 4, 5, 6, 7}), 'Every day');
    expect(repeatLabel({5, 1}), 'Mon, Fri');
    expect(
      relativeLabel(now.add(const Duration(minutes: 25)), now, kolkata),
      'in 25m',
    );
    expect(
      relativeLabel(DateTime.utc(2026, 12, 1, 12, 30), now, kolkata),
      'today 18:00',
    );
    expect(
      relativeLabel(DateTime.utc(2026, 12, 2, 1, 30), now, kolkata),
      'tomorrow 07:00',
    );
    expect(
      relativeLabel(DateTime.utc(2026, 12, 5, 1, 30), now, kolkata),
      'Sat 07:00',
    );
  });
}
