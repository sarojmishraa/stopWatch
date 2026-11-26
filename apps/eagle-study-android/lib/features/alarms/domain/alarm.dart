import '../../../core/time/study_calendar.dart';

/// How an alarm sounds. Voice styles speak the alarm message with Android
/// text-to-speech, so they need no bundled audio files.
enum AlarmSound {
  classic('Classic alarm', 'The phone’s default alarm tone'),
  voice('Spoken message', 'Reads your message aloud'),
  ghost('Ghost voice', 'Slow, low, echoing delivery'),
  monster('Monster voice', 'Very deep and slow'),
  whisper('Haunted whisper', 'Quiet, high and slow'),
  recording('My recording', 'Your own recorded voice');

  const AlarmSound(this.label, this.description);
  final String label;
  final String description;

  static AlarmSound parse(String? name) => AlarmSound.values.firstWhere(
    (s) => s.name == name,
    orElse: () => AlarmSound.classic,
  );
}

class Alarm {
  const Alarm({
    required this.id,
    required this.hour,
    required this.minute,
    this.days = const {},
    this.message = '',
    this.sound = AlarmSound.classic,
    this.volume = 0.8,
    this.vibrate = true,
    this.enabled = true,
    this.recordingPath,
  });

  final String id;
  final int hour;
  final int minute;

  /// ISO weekdays (1 = Monday … 7 = Sunday). Empty means ring once.
  final Set<int> days;
  final String message;
  final AlarmSound sound;

  /// 0.1–1.0, relative to the phone's alarm volume.
  final double volume;
  final bool vibrate;
  final bool enabled;
  final String? recordingPath;

  bool get repeats => days.isNotEmpty;

  /// Text spoken by voice styles and shown on the alarm screen.
  String get spokenText => message.trim().isEmpty
      ? 'Time to study. Wake up, eagle.'
      : message.trim();

  Alarm copyWith({
    int? hour,
    int? minute,
    Set<int>? days,
    String? message,
    AlarmSound? sound,
    double? volume,
    bool? vibrate,
    bool? enabled,
    String? recordingPath,
    bool clearRecording = false,
  }) => Alarm(
    id: id,
    hour: hour ?? this.hour,
    minute: minute ?? this.minute,
    days: days ?? this.days,
    message: message ?? this.message,
    sound: sound ?? this.sound,
    volume: volume ?? this.volume,
    vibrate: vibrate ?? this.vibrate,
    enabled: enabled ?? this.enabled,
    recordingPath: clearRecording ? null : recordingPath ?? this.recordingPath,
  );

  /// Problems that prevent saving; empty when valid.
  List<String> validate() => [
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) 'Invalid time.',
    if (days.any((d) => d < 1 || d > 7)) 'Invalid weekday.',
    if (message.length > 200) 'Message must be at most 200 characters.',
    if (volume < 0.1 || volume > 1) 'Volume must be between 10% and 100%.',
    if (sound == AlarmSound.recording && (recordingPath ?? '').isEmpty)
      'Record your voice first, or pick another sound.',
  ];

  /// Payload for the native scheduler (see AlarmSpec.kt).
  Map<String, Object?> toNative(String zone) => {
    'id': id,
    'hour': hour,
    'minute': minute,
    'days': days.toList()..sort(),
    'message': spokenText,
    'sound': sound.name,
    'volume': volume,
    'vibrate': vibrate,
    'recordingPath': recordingPath,
    'zone': zone,
  };
}

/// Next instant at or after [now] (exclusive) when [alarm] rings, in the
/// calendar's timezone. Mirrors NextTrigger.kt, which does the actual
/// scheduling on the device; both are tested against the same cases.
DateTime nextTrigger(Alarm alarm, DateTime now, StudyCalendar calendar) {
  final local = calendar.local(now);
  for (var offset = 0; offset <= 7; offset++) {
    final day = DateTime.utc(local.year, local.month, local.day + offset);
    final candidate = calendar.at(
      day.year,
      day.month,
      day.day,
      alarm.hour,
      alarm.minute,
    );
    if (!candidate.isAfter(now)) continue;
    if (!alarm.repeats || alarm.days.contains(day.weekday)) return candidate;
  }
  throw StateError('No trigger within a week for alarm ${alarm.id}');
}
