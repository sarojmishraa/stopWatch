enum TimerMode { stopwatch, countdown }

class StudyTimerState {
  const StudyTimerState({
    this.mode = TimerMode.stopwatch,
    this.isRunning = false,
    this.accumulatedSeconds = 0,
    this.segmentStartedAtMs,
    this.countdownEndAtMs,
    this.countdownDurationSeconds = 25 * 60,
    this.sessionStartedAtMs,
    this.laps = const [],
    this.todaySeconds = 0,
    this.weekSeconds = 0,
    this.sessionCount = 0,
    this.recentSessions = const [],
  });

  final TimerMode mode;
  final bool isRunning;
  final int accumulatedSeconds;
  final int? segmentStartedAtMs;
  final int? countdownEndAtMs;
  final int countdownDurationSeconds;
  final int? sessionStartedAtMs;
  final List<int> laps;
  final int todaySeconds;
  final int weekSeconds;
  final int sessionCount;
  final List<({int startedAtMs, int durationSeconds})> recentSessions;

  int secondsAt(int nowMs) {
    if (!isRunning) return accumulatedSeconds;
    if (mode == TimerMode.countdown) {
      final end = countdownEndAtMs;
      if (end == null) return accumulatedSeconds;
      return ((end - nowMs) / 1000).ceil().clamp(0, countdownDurationSeconds);
    }
    final started = segmentStartedAtMs;
    if (started == null) return accumulatedSeconds;
    return accumulatedSeconds +
        ((nowMs - started) / 1000).floor().clamp(0, 1 << 31);
  }

  Map<String, Object?> toMap() => {
    'mode': mode.name,
    'isRunning': isRunning,
    'accumulatedSeconds': accumulatedSeconds,
    'segmentStartedAtMs': segmentStartedAtMs,
    'countdownEndAtMs': countdownEndAtMs,
    'countdownDurationSeconds': countdownDurationSeconds,
    'sessionStartedAtMs': sessionStartedAtMs,
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
      sessionStartedAtMs: map['sessionStartedAtMs'] as int?,
      laps: (map['laps'] as List<dynamic>? ?? const []).cast<int>(),
    );
  }

  StudyTimerState copyWith({
    TimerMode? mode,
    bool? isRunning,
    int? accumulatedSeconds,
    int? segmentStartedAtMs,
    bool clearSegmentStartedAtMs = false,
    int? countdownEndAtMs,
    bool clearCountdownEndAtMs = false,
    int? countdownDurationSeconds,
    int? sessionStartedAtMs,
    bool clearSessionStartedAtMs = false,
    List<int>? laps,
    int? todaySeconds,
    int? weekSeconds,
    int? sessionCount,
    List<({int startedAtMs, int durationSeconds})>? recentSessions,
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
      sessionStartedAtMs: clearSessionStartedAtMs
          ? null
          : sessionStartedAtMs ?? this.sessionStartedAtMs,
      laps: laps ?? this.laps,
      todaySeconds: todaySeconds ?? this.todaySeconds,
      weekSeconds: weekSeconds ?? this.weekSeconds,
      sessionCount: sessionCount ?? this.sessionCount,
      recentSessions: recentSessions ?? this.recentSessions,
    );
  }
}
