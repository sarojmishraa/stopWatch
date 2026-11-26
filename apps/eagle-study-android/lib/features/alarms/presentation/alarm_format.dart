import '../../../core/time/study_calendar.dart';
import '../../sessions/presentation/session_format.dart';

const _short = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String timeLabel(int hour, int minute) =>
    '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

/// `Once`, `Every day`, `Weekdays`, `Weekends`, or `Mon, Wed, Fri`.
String repeatLabel(Set<int> days) {
  if (days.isEmpty) return 'Once';
  if (days.length == 7) return 'Every day';
  if (days.length == 5 && days.containsAll({1, 2, 3, 4, 5})) return 'Weekdays';
  if (days.length == 2 && days.containsAll({6, 7})) return 'Weekends';
  return (days.toList()..sort()).map((d) => _short[d - 1]).join(', ');
}

/// `in 45m`, `in 3h 10m (today 18:00)`, `tomorrow 07:00`, `Sat 07:00`.
String relativeLabel(DateTime at, DateTime now, StudyCalendar calendar) {
  final local = calendar.local(at);
  final clock = clockTime(local);
  final until = at.difference(now);
  if (until.inMinutes < 60) return 'in ${formatDuration(until.inSeconds)}';
  final today = calendar.dayKey(now);
  final tomorrow = calendar.dayKey(now.add(const Duration(days: 1)));
  final day = calendar.dayKey(at);
  if (day == today) return 'today $clock';
  if (day == tomorrow) return 'tomorrow $clock';
  return '${_short[local.weekday - 1]} $clock';
}
