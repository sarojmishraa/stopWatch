/// Shared formatting for durations and times on session screens.
library;

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// `1h 05m`, `25m`, or `40s` for very short sessions.
String formatDuration(int seconds) {
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  if (hours > 0) return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
  if (minutes > 0) return '${minutes}m';
  return '${seconds}s';
}

/// `MM:SS`, or `HH:MM:SS` from one hour.
String formatClock(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

/// 24-hour `HH:MM` of a local (study-timezone) time.
String clockTime(DateTime local) =>
    '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';

/// `Tue, 1 Dec 2026` for a local (study-timezone) date.
String dayLabel(DateTime local) =>
    '${_weekdays[local.weekday - 1]}, ${local.day} ${_months[local.month - 1]} ${local.year}';
