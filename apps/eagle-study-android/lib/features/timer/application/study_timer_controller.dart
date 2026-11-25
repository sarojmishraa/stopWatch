import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/providers.dart';
import '../../sessions/domain/study_session.dart';
import '../domain/study_timer_state.dart';

final studyTimerProvider =
    NotifierProvider<StudyTimerController, StudyTimerState>(
      StudyTimerController.new,
    );

enum FinishOutcome {
  /// Session saved to the device and queued for sync.
  saved,

  /// Saved, but focused time was capped at 24 hours.
  savedCapped,

  /// Less than one second of focus: discarded, nothing saved.
  tooShort,

  /// No session in progress.
  nothingToFinish,
}

class StudyTimerController extends Notifier<StudyTimerState> {
  Timer? _completionTimer;
  bool _finishing = false;
  bool _userActed = false;

  int get _nowMs => ref.read(clockProvider)().millisecondsSinceEpoch;

  @override
  StudyTimerState build() {
    ref.onDispose(() => _completionTimer?.cancel());
    unawaited(_restore());
    return const StudyTimerState();
  }

  /// Completes once the persisted timer (if any) has been restored.
  late final Future<void> ready = _restoreCompleter.future;
  final _restoreCompleter = Completer<void>();

  Future<void> _restore() async {
    try {
      final saved = await ref.read(studyDatabaseProvider).loadTimerState();
      if (!ref.mounted || _userActed || saved == null) return;
      var restored = StudyTimerState.fromMap(saved);
      // Timers persisted by an older app version have no session ID yet.
      if (restored.sessionStartedAtMs != null && restored.sessionId == null) {
        restored = restored.copyWith(sessionId: const Uuid().v4());
      }
      state = restored;
      _scheduleCompletion();
      await checkCountdown();
    } finally {
      if (!_restoreCompleter.isCompleted) _restoreCompleter.complete();
    }
  }

  void selectMode(TimerMode mode) {
    if (state.hasSession || state.mode == mode) return;
    _touch();
    state = StudyTimerState(
      mode: mode,
      countdownDurationSeconds: state.countdownDurationSeconds,
      accumulatedSeconds: mode == TimerMode.countdown
          ? state.countdownDurationSeconds
          : 0,
      subject: state.subject,
    );
    _persist();
  }

  /// Returns false if [seconds] is out of range or a session is in progress.
  bool setCountdownDuration(int seconds) {
    if (state.hasSession || seconds < 1 || seconds > maxSessionSeconds) {
      return false;
    }
    _touch();
    state = StudyTimerState(
      mode: TimerMode.countdown,
      countdownDurationSeconds: seconds,
      accumulatedSeconds: seconds,
      subject: state.subject,
    );
    _persist();
    return true;
  }

  void setSubject(String? subject) {
    _touch();
    state = subject == null
        ? state.copyWith(clearSubject: true)
        : state.copyWith(subject: subject);
    _persist();
  }

  void startOrResume() {
    if (state.isRunning) {
      pause();
      return;
    }
    _touch();
    final now = _nowMs;
    final isCountdown = state.mode == TimerMode.countdown;
    final remaining = state.accumulatedSeconds > 0
        ? state.accumulatedSeconds
        : state.countdownDurationSeconds;
    state = state.copyWith(
      isRunning: true,
      segmentStartedAtMs: isCountdown ? null : now,
      clearSegmentStartedAtMs: isCountdown,
      countdownEndAtMs: isCountdown ? now + remaining * 1000 : null,
      clearCountdownEndAtMs: !isCountdown,
      accumulatedSeconds: isCountdown ? remaining : null,
      sessionId: state.sessionId ?? const Uuid().v4(),
      sessionStartedAtMs: state.sessionStartedAtMs ?? now,
      clearPausedAtMs: true,
    );
    _scheduleCompletion();
    _persist();
  }

  void pause() {
    if (!state.isRunning) return;
    _touch();
    final now = _nowMs;
    state = state.copyWith(
      isRunning: false,
      accumulatedSeconds: state.secondsAt(now),
      clearSegmentStartedAtMs: true,
      clearCountdownEndAtMs: true,
      pausedAtMs: now,
    );
    _completionTimer?.cancel();
    _persist();
  }

  /// Records a lap. Returns false when not possible (not running, or the
  /// 500-lap limit is reached).
  bool addLap() {
    if (state.mode != TimerMode.stopwatch || !state.isRunning) return false;
    if (state.laps.length >= maxLaps) return false;
    _touch();
    state = state.copyWith(laps: [...state.laps, state.secondsAt(_nowMs)]);
    _persist();
    return true;
  }

  /// Ends the session early (or a stopwatch session) and saves it.
  Future<FinishOutcome> finish() async {
    _touch();
    if (!state.hasSession) return FinishOutcome.nothingToFinish;
    final now = _nowMs;
    final endMs = state.isRunning ? now : (state.pausedAtMs ?? now);
    return _save(focusedSeconds: state.focusedSecondsAt(now), endMs: endMs);
  }

  /// Discards the current session without saving it.
  Future<void> reset() async {
    _touch();
    _completionTimer?.cancel();
    state = state.idle();
    await ref.read(studyDatabaseProvider).clearTimerState();
    _persist();
  }

  /// Saves a countdown whose end time has passed. Runs on a timer, on
  /// restore and when the app returns to the foreground, so a countdown that
  /// ended while the app was suspended or killed is recorded with its real
  /// end time.
  Future<void> checkCountdown() async {
    final end = state.countdownEndAtMs;
    if (!state.isRunning || state.mode != TimerMode.countdown || end == null) {
      return;
    }
    if (_nowMs < end) {
      _scheduleCompletion();
      return;
    }
    await _save(focusedSeconds: state.countdownDurationSeconds, endMs: end);
  }

  Future<FinishOutcome> _save({
    required int focusedSeconds,
    required int endMs,
  }) async {
    if (_finishing) return FinishOutcome.nothingToFinish;
    _finishing = true;
    try {
      _completionTimer?.cancel();
      final id = state.sessionId!;
      final startMs = state.sessionStartedAtMs!;
      if (focusedSeconds < 1) {
        await reset();
        return FinishOutcome.tooShort;
      }
      final capped = focusedSeconds > maxSessionSeconds;
      final focused = math.min(focusedSeconds, maxSessionSeconds);
      // If the device clock was moved backwards mid-session, the wall-clock
      // span could be shorter than the focused time. Keep the measured focus
      // and stretch the end time rather than losing the session.
      final safeEndMs = math.max(endMs, startMs + focused * 1000);
      final repository = ref.read(sessionRepositoryProvider);
      final record = StudySessionRecord(
        id: id,
        mode: state.mode == TimerMode.countdown
            ? SessionMode.countdown
            : SessionMode.stopwatch,
        startedAt: DateTime.fromMillisecondsSinceEpoch(startMs, isUtc: true),
        endedAt: DateTime.fromMillisecondsSinceEpoch(safeEndMs, isUtc: true),
        durationSeconds: focused,
        plannedSeconds: state.mode == TimerMode.countdown
            ? state.countdownDurationSeconds
            : null,
        subject: state.subject,
        lapsSeconds: state.laps.where((lap) => lap <= focused).toList(),
        sourceDevice: await repository.deviceId(),
        clientUpdatedAt: ref.read(clockProvider)().toUtc(),
      );
      await repository.completeSession(record);
      if (!ref.mounted) return FinishOutcome.saved;
      state = state.idle(
        lastSaved: SavedSessionNotice(
          sessionId: id,
          durationSeconds: focused,
          capped: capped,
        ),
      );
      _persist();
      ref.invalidate(studySummaryProvider);
      return capped ? FinishOutcome.savedCapped : FinishOutcome.saved;
    } finally {
      _finishing = false;
    }
  }

  void _scheduleCompletion() {
    _completionTimer?.cancel();
    final end = state.countdownEndAtMs;
    if (!state.isRunning || state.mode != TimerMode.countdown || end == null) {
      return;
    }
    final wait = Duration(milliseconds: math.max(0, end - _nowMs));
    _completionTimer = Timer(wait, () => unawaited(checkCountdown()));
  }

  void _touch() => _userActed = true;

  void _persist() {
    unawaited(ref.read(studyDatabaseProvider).saveTimerState(state.toMap()));
  }
}
