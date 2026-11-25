enum TimerMode { stopwatch, countdown }

/// The running (or paused) timer. It's persisted on every change so the
/// session survives process death.
///
/// Elapsed time is always derived from wall-clock anchors
/// ([segmentStartedAtMs], [countdownEndAtMs]), never from counting ticks, so
/// it stays correct while the app is backgrounded or killed.
class StudyTimerState {
  const StudyTimerState({
    this.mode = TimerMode.stopwatch,
    this.isRunning = false,
    this.accumulatedSeconds = 0,
    this.segmentStartedAtMs,
    this.countdownEndAtMs,
    this.countdownDurationSeconds = 25 * 60,
    this.sessionId,
    this.sessionStartedAtMs,
    this.pausedAtMs,
    this.subject,
    this.laps = const [],
    this.lastSaved,
  });

  final TimerMode mode;
  final bool isRunning;

  /// Stopwatch: focused seconds before the current segment.
  /// Countdown: seconds remaining when last paused.
  final int accumulatedSeconds;
  final int? segmentStartedAtMs;
  final int? countdownEndAtMs;
  final int countdownDurationSeconds;

  /// Assigned when the session first starts; becomes the record's UUID.
  final String? sessionId;
  final int? sessionStartedAtMs;
  final int? pausedAtMs;
  final String? subject;

  /// Cumulative lap marks in seconds.
  final List<int> laps;

  /// The last session saved in this process (not persisted). The UI uses it
  /// to confirm a save; the eagle celebration will hook in here too.
  final SavedSessionNotice? lastSaved;

  bool get hasSession => sessionId != null;

  int secondsAt(int nowMs) {
    if (!isRunning) return accumulatedSeconds;
    if (mode == TimerMode.countdown) {
      final end = countdownEndAtMs;
      if (end == null) return accumulatedSeconds;
      return ((end - nowMs) / 1000).ceil().clamp(0, countdownDurationSeconds);
    }
    final started = segmentStartedAtMs;
    if (started == null) return accumulatedSeconds;
    return accumulatedSeconds + ((nowMs - started) ~/ 1000).clamp(0, 1 << 31);
  }

  /// Focused seconds so far, whatever the mode.
  int focusedSecondsAt(int nowMs) => mode == TimerMode.countdown
      ? countdownDurationSeconds - secondsAt(nowMs)
      : secondsAt(nowMs);

  Map<String, Object?> toMap() => {
    'mode': mode.name,
    'isRunning': isRunning,
    'accumulatedSeconds': accumulatedSeconds,
    'segmentStartedAtMs': segmentStartedAtMs,
    'countdownEndAtMs': countdownEndAtMs,
    'countdownDurationSeconds': countdownDurationSeconds,
    'sessionId': sessionId,
    'sessionStartedAtMs': sessionStartedAtMs,
    'pausedAtMs': pausedAtMs,
    'subject': subject,
    'laps': laps,
  };

  factory StudyTimerState.fromMap(Map<String, dynamic> map) {
    return StudyTimerState(
      mode: TimerMode.values.firstWhere(
        (mode) => mode.name == map['mode'],
        orElse: () => TimerMode.stopwatch,
      ),
      isRunning: map['isRunning'] as bool? ?? false,
      accumulatedSeconds: map['accumulatedSeconds'] as int? ?? 0,
      segmentStartedAtMs: map['segmentStartedAtMs'] as int?,
      countdownEndAtMs: map['countdownEndAtMs'] as int?,
      countdownDurationSeconds: map['countdownDurationSeconds'] as int? ?? 1500,
      sessionId: map['sessionId'] as String?,
      sessionStartedAtMs: map['sessionStartedAtMs'] as int?,
      pausedAtMs: map['pausedAtMs'] as int?,
      subject: map['subject'] as String?,
      laps: (map['laps'] as List<dynamic>? ?? const []).cast<int>(),
    );
  }

  /// A fresh, idle timer that keeps the user's mode, duration and subject.
  StudyTimerState idle({SavedSessionNotice? lastSaved}) => StudyTimerState(
    mode: mode,
    countdownDurationSeconds: countdownDurationSeconds,
    accumulatedSeconds: mode == TimerMode.countdown
        ? countdownDurationSeconds
        : 0,
    subject: subject,
    lastSaved: lastSaved ?? this.lastSaved,
  );

  StudyTimerState copyWith({
    TimerMode? mode,
    bool? isRunning,
    int? accumulatedSeconds,
    int? segmentStartedAtMs,
    bool clearSegmentStartedAtMs = false,
    int? countdownEndAtMs,
    bool clearCountdownEndAtMs = false,
    int? countdownDurationSeconds,
    String? sessionId,
    int? sessionStartedAtMs,
    int? pausedAtMs,
    bool clearPausedAtMs = false,
    String? subject,
    bool clearSubject = false,
    List<int>? laps,
  }) {
    return StudyTimerState(
      mode: mode ?? this.mode,
      isRunning: isRunning ?? this.isRunning,
      accumulatedSeconds: accumulatedSeconds ?? this.accumulatedSeconds,
      segmentStartedAtMs: clearSegmentStartedAtMs
          ? null
          : segmentStartedAtMs ?? this.segmentStartedAtMs,
      countdownEndAtMs: clearCountdownEndAtMs
          ? null
          : countdownEndAtMs ?? this.countdownEndAtMs,
      countdownDurationSeconds:
          countdownDurationSeconds ?? this.countdownDurationSeconds,
      sessionId: sessionId ?? this.sessionId,
      sessionStartedAtMs: sessionStartedAtMs ?? this.sessionStartedAtMs,
      pausedAtMs: clearPausedAtMs ? null : pausedAtMs ?? this.pausedAtMs,
      subject: clearSubject ? null : subject ?? this.subject,
      laps: laps ?? this.laps,
      lastSaved: lastSaved,
    );
  }
}

class SavedSessionNotice {
  const SavedSessionNotice({
    required this.sessionId,
    required this.durationSeconds,
    required this.capped,
  });

  final String sessionId;
  final int durationSeconds;

  /// True when focused time was capped at 24 hours.
  final bool capped;
}
