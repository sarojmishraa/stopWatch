/// A completed study session as stored on the device and synced to the API.
///
/// Field rules mirror the server (see backend/api-contracts/openapi.yaml), so
/// a record that passes [validate] will not be rejected when it syncs.
library;

enum SessionMode { stopwatch, countdown, pomodoro }

/// Subjects offered in the timer. Free text is also accepted by the API.
const studySubjects = [
  'Java',
  'Go',
  'DSA',
  'Distributed Systems',
  'System Design',
  'Platform & Cloud',
  'Interview Prep',
  'Other',
];

const maxSessionSeconds = 86400;
const maxLaps = 500;
const maxSubjectLength = 120;
const maxNotesLength = 4000;

class StudySessionRecord {
  const StudySessionRecord({
    required this.id,
    required this.mode,
    required this.startedAt,
    required this.endedAt,
    required this.durationSeconds,
    required this.sourceDevice,
    required this.clientUpdatedAt,
    this.plannedSeconds,
    this.subject,
    this.notes,
    this.lapsSeconds = const [],
    this.deletedAt,
  });

  final String id;
  final SessionMode mode;
  final DateTime startedAt;
  final DateTime endedAt;

  /// Focused seconds; pauses make this shorter than [endedAt] − [startedAt].
  final int durationSeconds;
  final int? plannedSeconds;
  final String? subject;
  final String? notes;

  /// Cumulative lap marks in seconds since the session started.
  final List<int> lapsSeconds;
  final String sourceDevice;

  /// When this version was last edited on the device (sync conflict key).
  final DateTime clientUpdatedAt;
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;

  /// Problems that would make the server reject this record; empty if valid.
  List<String> validate() {
    final errors = <String>[];
    if (endedAt.isBefore(startedAt)) {
      errors.add('Session ends before it starts.');
    }
    if (durationSeconds < 1 || durationSeconds > maxSessionSeconds) {
      errors.add('Duration must be between 1 second and 24 hours.');
    }
    final spanMs = endedAt.difference(startedAt).inMilliseconds;
    if (durationSeconds * 1000 > spanMs + 1000) {
      errors.add('Focused time cannot exceed the time between start and end.');
    }
    final planned = plannedSeconds;
    if (planned != null && (planned < 1 || planned > maxSessionSeconds)) {
      errors.add('Planned duration must be between 1 second and 24 hours.');
    }
    if ((subject?.length ?? 0) > maxSubjectLength) {
      errors.add('Subject is too long.');
    }
    if ((notes?.length ?? 0) > maxNotesLength) {
      errors.add('Notes are too long.');
    }
    if (lapsSeconds.length > maxLaps) {
      errors.add('Too many laps.');
    }
    var previous = 0;
    for (final lap in lapsSeconds) {
      if (lap < previous || lap > durationSeconds) {
        errors.add('Laps must be in order and within the session.');
        break;
      }
      previous = lap;
    }
    if (sourceDevice.trim().isEmpty) {
      errors.add('Device ID is missing.');
    }
    return errors;
  }

  StudySessionRecord copyWith({
    String? subject,
    bool clearSubject = false,
    String? notes,
    bool clearNotes = false,
    DateTime? clientUpdatedAt,
    DateTime? deletedAt,
  }) {
    return StudySessionRecord(
      id: id,
      mode: mode,
      startedAt: startedAt,
      endedAt: endedAt,
      durationSeconds: durationSeconds,
      plannedSeconds: plannedSeconds,
      subject: clearSubject ? null : subject ?? this.subject,
      notes: clearNotes ? null : notes ?? this.notes,
      lapsSeconds: lapsSeconds,
      sourceDevice: sourceDevice,
      clientUpdatedAt: clientUpdatedAt ?? this.clientUpdatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  /// Request body for `PUT /v1/study-sessions/{id}`.
  Map<String, Object?> toApiJson() => {
    'mode': mode.name,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'endedAt': endedAt.toUtc().toIso8601String(),
    'durationSeconds': durationSeconds,
    'plannedSeconds': plannedSeconds,
    'subject': subject,
    'notes': notes,
    'lapsSeconds': lapsSeconds,
    'sourceDevice': sourceDevice,
    'clientUpdatedAt': clientUpdatedAt.toUtc().toIso8601String(),
  };

  /// Parses a session object returned by the Go API (`/v1/study-sessions` or
  /// `/v1/sync/study-sessions`).
  factory StudySessionRecord.fromApiJson(Map<String, dynamic> json) {
    final deletedRaw = json['deletedAt'] as String?;
    return StudySessionRecord(
      id: json['id']! as String,
      mode: SessionMode.values.byName(json['mode']! as String),
      startedAt: DateTime.parse(json['startedAt']! as String).toUtc(),
      endedAt: DateTime.parse(json['endedAt']! as String).toUtc(),
      durationSeconds: (json['durationSeconds']! as num).toInt(),
      plannedSeconds: (json['plannedSeconds'] as num?)?.toInt(),
      subject: json['subject'] as String?,
      notes: json['notes'] as String?,
      lapsSeconds: ((json['lapsSeconds'] as List<dynamic>?) ?? const [])
          .map((e) => (e as num).toInt())
          .toList(),
      sourceDevice: json['sourceDevice']! as String,
      clientUpdatedAt:
          DateTime.parse(json['clientUpdatedAt']! as String).toUtc(),
      deletedAt: deletedRaw == null ? null : DateTime.parse(deletedRaw).toUtc(),
    );
  }
}

class StudySummary {
  const StudySummary({
    required this.todaySeconds,
    required this.weekSeconds,
    required this.monthSeconds,
    required this.todaySessions,
    required this.totalSessions,
    required this.dailyTargetMinutes,
    required this.weeklyTargetMinutes,
    required this.recent,
    required this.pendingSync,
  });

  static const empty = StudySummary(
    todaySeconds: 0,
    weekSeconds: 0,
    monthSeconds: 0,
    todaySessions: 0,
    totalSessions: 0,
    dailyTargetMinutes: defaultDailyTargetMinutes,
    weeklyTargetMinutes: defaultWeeklyTargetMinutes,
    recent: [],
    pendingSync: 0,
  );

  /// 6 h/day average and 50 h/week, matching the study plan and API defaults.
  static const defaultDailyTargetMinutes = 360;
  static const defaultWeeklyTargetMinutes = 3000;

  final int todaySeconds;
  final int weekSeconds;
  final int monthSeconds;
  final int todaySessions;
  final int totalSessions;
  final int dailyTargetMinutes;
  final int weeklyTargetMinutes;
  final List<StudySessionRecord> recent;

  /// Local changes not yet uploaded to the API.
  final int pendingSync;
}
