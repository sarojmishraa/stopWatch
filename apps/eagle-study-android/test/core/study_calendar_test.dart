import 'package:eagle_study/core/time/study_calendar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final kolkata = StudyCalendar.kolkata();

  test('a UTC evening instant belongs to the next day in Asia/Kolkata', () {
    final instant = DateTime.utc(2026, 11, 30, 18, 45); // 00:15 IST, 1 Dec
    expect(kolkata.dayKey(instant), '2026-12-01');
    expect(
      kolkata.startOfDay(instant).toUtc(),
      DateTime.utc(2026, 11, 30, 18, 30),
    );
  });

  test('weeks start on Monday, including across a month boundary', () {
    final tuesday = DateTime.utc(2026, 12, 1, 4, 30); // Tue 1 Dec 10:00 IST
    final sunday = DateTime.utc(2026, 12, 6, 17, 30); // Sun 6 Dec 23:00 IST
    final monday = DateTime.utc(2026, 11, 29, 18, 30); // Mon 30 Nov 00:00 IST
    expect(kolkata.startOfWeek(tuesday).toUtc(), monday);
    expect(kolkata.startOfWeek(sunday).toUtc(), monday);
    // 1 Dec 00:00 IST, not the Monday.
    expect(
      kolkata.startOfMonth(tuesday).toUtc(),
      DateTime.utc(2026, 11, 30, 18, 30),
    );
  });

  test('uses zone rules, not a fixed offset, for zones with DST', () {
    final berlin = StudyCalendar('Europe/Berlin');
    // Tue 30 Mar 2027 is in summer time (UTC+2); the week began Mon 29 Mar.
    final tuesday = DateTime.utc(2027, 3, 30, 10);
    expect(berlin.startOfWeek(tuesday).toUtc(), DateTime.utc(2027, 3, 28, 22));
    // 28 Mar 2027 is the switch day: midnight was still UTC+1.
    expect(
      berlin.startOfDay(DateTime.utc(2027, 3, 28, 12)).toUtc(),
      DateTime.utc(2027, 3, 27, 23),
    );
  });
}
