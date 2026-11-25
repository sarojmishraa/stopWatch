import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Wall-clock source. Overridden in tests so time-based logic is deterministic.
typedef Clock = DateTime Function();

bool _initialized = false;

/// Loads the IANA timezone database. Safe to call more than once.
void initializeTimeZones() {
  if (_initialized) return;
  tzdata.initializeTimeZones();
  _initialized = true;
}

/// Calendar arithmetic in the study timezone (Asia/Kolkata by default).
///
/// Every boundary is computed from the IANA zone rules, not a fixed offset,
/// so it stays correct if the user later picks a zone with daylight saving.
/// Weeks start on Monday (ISO 8601), matching the server's summary.
class StudyCalendar {
  StudyCalendar(String zone) : location = _location(zone);

  factory StudyCalendar.kolkata() => StudyCalendar(defaultZone);

  static const defaultZone = 'Asia/Kolkata';

  final tz.Location location;

  static tz.Location _location(String zone) {
    initializeTimeZones();
    return tz.getLocation(zone);
  }

  tz.TZDateTime local(DateTime instant) =>
      tz.TZDateTime.from(instant, location);

  /// The instant of local midnight that starts the day containing [instant].
  DateTime startOfDay(DateTime instant) {
    final l = local(instant);
    return tz.TZDateTime(location, l.year, l.month, l.day);
  }

  DateTime startOfWeek(DateTime instant) {
    final l = local(instant);
    // Do the day arithmetic on a plain UTC date, which rolls over month and
    // year boundaries; TZDateTime does not normalise day 0 or negative days.
    final monday = DateTime.utc(l.year, l.month, l.day - (l.weekday - 1));
    return tz.TZDateTime(location, monday.year, monday.month, monday.day);
  }

  DateTime startOfMonth(DateTime instant) {
    final l = local(instant);
    return tz.TZDateTime(location, l.year, l.month);
  }

  /// `YYYY-MM-DD` of [instant] in the study timezone.
  String dayKey(DateTime instant) {
    final l = local(instant);
    return '${l.year.toString().padLeft(4, '0')}-'
        '${l.month.toString().padLeft(2, '0')}-'
        '${l.day.toString().padLeft(2, '0')}';
  }
}
