import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/study_database.dart';
import '../domain/study_timer_state.dart';

final studyDatabaseProvider = Provider<StudyDatabase>((ref) {
  return StudyDatabase();
});

final studyTimerProvider =
    NotifierProvider<StudyTimerController, StudyTimerState>(
      StudyTimerController.new,
    );

class StudyTimerController extends Notifier<StudyTimerState> {
  Timer? _ticker;
  bool _completionInProgress = false;

  StudyDatabase get _database => ref.read(studyDatabaseProvider);

  @override
  StudyTimerState build() {
    ref.onDispose(() => _ticker?.cancel());
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => refresh());
    unawaited(_restore());
    return const StudyTimerState();
  }

  Future<void> _restore() async {
    final saved = await _database.loadTimerState();
    final summary = await _database.loadSummary();
    if (!ref.mounted) return;
    state =
        (saved == null
                ? const StudyTimerState()
                : StudyTimerState.fromMap(saved))
            .copyWith(
              todaySeconds: summary.todaySeconds,
              weekSeconds: summary.weekSeconds,
              sessionCount: summary.sessionCount,
              recentSessions: summary.recentSessions
                  .map(
                    (session) => (
                      startedAtMs: session.startedAt.millisecondsSinceEpoch,
                      durationSeconds: session.durationSeconds,
                    ),
                  )
                  .toList(),
            );
    refresh();
  }

  void refresh() {
    if (state.isRunning &&
        state.mode == TimerMode.countdown &&
        state.secondsAt(DateTime.now().millisecondsSinceEpoch) == 0) {
      unawaited(_completeCountdown());
      return;
    }
    state = state.copyWith();
  }

  void selectMode(TimerMode mode) {
    if (state.isRunning || state.mode == mode) return;
    state = StudyTimerState(
      mode: mode,
      countdownDurationSeconds: state.countdownDurationSeconds,
      todaySeconds: state.todaySeconds,
      weekSeconds: state.weekSeconds,
      sessionCount: state.sessionCount,
      recentSessions: state.recentSessions,
    );
    unawaited(_persist());
  }

  void setCountdownPreset(int minutes) {
    if (minutes <= 0) return;
    setCountdownDuration(minutes * 60);
  }

  void setCountdownDuration(int seconds) {
    if (state.isRunning || seconds <= 0) return;
    state = state.copyWith(
      mode: TimerMode.countdown,
      accumulatedSeconds: seconds,
      countdownDurationSeconds: seconds,
      clearSegmentStartedAtMs: true,
      clearCountdownEndAtMs: true,
      clearSessionStartedAtMs: true,
      laps: const [],
    );
    unawaited(_persist());
  }

  void startOrResume() {
    if (state.isRunning) {
      pause();
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final countdownSeconds = state.mode == TimerMode.countdown
        ? (state.accumulatedSeconds == 0
              ? state.countdownDurationSeconds
              : state.accumulatedSeconds)
        : state.accumulatedSeconds;
    state = state.copyWith(
      isRunning: true,
      segmentStartedAtMs: state.mode == TimerMode.stopwatch ? now : null,
      clearSegmentStartedAtMs: state.mode == TimerMode.countdown,
      countdownEndAtMs: state.mode == TimerMode.countdown
          ? now + countdownSeconds * 1000
          : null,
      clearCountdownEndAtMs: state.mode == TimerMode.stopwatch,
      sessionStartedAtMs: state.sessionStartedAtMs ?? now,
    );
    unawaited(_persist());
  }

  void pause() {
    if (!state.isRunning) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    state = state.copyWith(
      isRunning: false,
      accumulatedSeconds: state.secondsAt(now),
      clearSegmentStartedAtMs: true,
      clearCountdownEndAtMs: true,
    );
    unawaited(_persist());
  }

  void addLap() {
    if (state.mode != TimerMode.stopwatch || !state.isRunning) return;
    final elapsed = state.secondsAt(DateTime.now().millisecondsSinceEpoch);
    state = state.copyWith(laps: [...state.laps, elapsed]);
    unawaited(_persist());
  }

  Future<void> finish() async {
    final elapsed = state.mode == TimerMode.countdown
        ? state.countdownDurationSeconds -
              state.secondsAt(DateTime.now().millisecondsSinceEpoch)
        : state.isRunning
        ? state.secondsAt(DateTime.now().millisecondsSinceEpoch)
        : state.accumulatedSeconds;
    if (state.isRunning) {
      state = state.copyWith(
        isRunning: false,
        accumulatedSeconds: state.secondsAt(
          DateTime.now().millisecondsSinceEpoch,
        ),
        clearSegmentStartedAtMs: true,
        clearCountdownEndAtMs: true,
      );
    }
    await _saveCompletedSession(completedSeconds: elapsed);
  }

  Future<void> reset() async {
    final mode = state.mode;
    final duration = state.countdownDurationSeconds;
    state = StudyTimerState(
      mode: mode,
      countdownDurationSeconds: duration,
      accumulatedSeconds: mode == TimerMode.countdown ? duration : 0,
      todaySeconds: state.todaySeconds,
      weekSeconds: state.weekSeconds,
      sessionCount: state.sessionCount,
      recentSessions: state.recentSessions,
    );
    await _database.clearTimerState();
  }

  Future<void> _completeCountdown() async {
    if (_completionInProgress) return;
    _completionInProgress = true;
    state = state.copyWith(
      isRunning: false,
      accumulatedSeconds: 0,
      clearCountdownEndAtMs: true,
      clearSegmentStartedAtMs: true,
    );
    await _saveCompletedSession(
      completedSeconds: state.countdownDurationSeconds,
    );
    _completionInProgress = false;
  }

  Future<void> _saveCompletedSession({int? completedSeconds}) async {
    final startedAt = state.sessionStartedAtMs;
    final seconds =
        completedSeconds ??
        (state.mode == TimerMode.countdown
            ? state.countdownDurationSeconds
            : state.accumulatedSeconds);
    if (startedAt != null && seconds > 0) {
      await _database.saveSession(
        startedAt: DateTime.fromMillisecondsSinceEpoch(startedAt),
        durationSeconds: seconds,
      );
    }
    final summary = await _database.loadSummary();
    state = state.copyWith(
      isRunning: false,
      accumulatedSeconds: state.mode == TimerMode.countdown
          ? state.countdownDurationSeconds
          : 0,
      clearSegmentStartedAtMs: true,
      clearCountdownEndAtMs: true,
      clearSessionStartedAtMs: true,
      laps: const [],
      todaySeconds: summary.todaySeconds,
      weekSeconds: summary.weekSeconds,
      sessionCount: summary.sessionCount,
      recentSessions: summary.recentSessions
          .map(
            (session) => (
              startedAtMs: session.startedAt.millisecondsSinceEpoch,
              durationSeconds: session.durationSeconds,
            ),
          )
          .toList(),
    );
    await _persist();
  }

  Future<void> _persist() => _database.saveTimerState(state.toMap());
}
