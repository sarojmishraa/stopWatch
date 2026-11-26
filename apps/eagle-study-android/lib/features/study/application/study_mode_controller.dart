import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/providers.dart';
import '../../timer/application/study_timer_controller.dart';
import '../../timer/domain/study_timer_state.dart';
import '../data/study_mode_bridge.dart';
import '../domain/study_mode_prefs.dart';

final studyModeBridgeProvider = Provider<StudyModeBridge>(
  (ref) => MethodChannelStudyModeBridge(),
);

final studyModePrefsProvider =
    AsyncNotifierProvider<StudyModePrefsController, StudyModePrefs>(
      StudyModePrefsController.new,
    );

class StudyModePrefsController extends AsyncNotifier<StudyModePrefs> {
  static const _key = 'study_mode_prefs';

  @override
  Future<StudyModePrefs> build() async {
    final db = await ref.read(studyDatabaseProvider).database;
    final rows = await db.query(
      'app_state',
      where: 'key = ?',
      whereArgs: [_key],
    );
    if (rows.isEmpty) return const StudyModePrefs();
    return StudyModePrefs.fromJson(
      jsonDecode(rows.single['value']! as String) as Map<String, dynamic>,
    );
  }

  Future<void> save(StudyModePrefs prefs) async {
    final db = await ref.read(studyDatabaseProvider).database;
    await db.insert('app_state', {
      'key': _key,
      'value': jsonEncode(prefs.toJson()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    state = AsyncData(prefs);
    await ref.read(studyModeProvider.notifier).reapply();
  }
}

/// Whether Do Not Disturb access is granted. Re-read on app resume.
final dndAccessProvider = FutureProvider<bool>((ref) async {
  try {
    return await ref.watch(studyModeBridgeProvider).dndAccess();
  } catch (error) {
    debugPrint('DND access unknown: $error');
    return false;
  }
});

class StudyModeState {
  const StudyModeState({
    this.active = false,
    this.dndApplied = false,
    this.notice,
  });

  final bool active;

  /// Study Mode changed DND and will restore it on exit.
  final bool dndApplied;

  /// Something the user should know (e.g. DND access missing).
  final String? notice;
}

final studyModeProvider = NotifierProvider<StudyModeController, StudyModeState>(
  StudyModeController.new,
);

/// Study Mode = the full-screen study screen is open. Entering applies the
/// user's screen-awake and Do Not Disturb choices; leaving restores them.
class StudyModeController extends Notifier<StudyModeState> {
  StudyModeBridge get _bridge => ref.read(studyModeBridgeProvider);

  @override
  StudyModeState build() => const StudyModeState();

  Future<void> enter() async {
    if (state.active) return;
    state = const StudyModeState(active: true);
    await _apply();
  }

  Future<void> exit() async {
    if (!state.active) return;
    state = const StudyModeState();
    await _guard('keep the screen on', () => _bridge.setKeepScreenOn(false));
    await _guard('restore Do Not Disturb', _bridge.exitDnd);
  }

  /// Re-applies preferences changed while Study Mode is open.
  Future<void> reapply() async {
    if (state.active) await _apply();
  }

  /// If the app was killed while Study Mode had DND on, restore it now.
  Future<void> healAfterRestart() async {
    if (state.active) return;
    await _guard('restore Do Not Disturb', () async {
      if (await _bridge.dndActive()) await _bridge.exitDnd();
    });
  }

  Future<void> _apply() async {
    final prefs = await ref.read(studyModePrefsProvider.future);
    await _guard(
      'keep the screen on',
      () => _bridge.setKeepScreenOn(prefs.keepScreenOn),
    );
    if (prefs.dnd == DndMode.off) {
      await _guard('restore Do Not Disturb', _bridge.exitDnd);
      state = const StudyModeState(active: true);
      return;
    }
    var applied = false;
    await _guard('turn on Do Not Disturb', () async {
      applied = await _bridge.enterDnd(prefs.dnd.name);
    });
    if (!state.active) {
      // Left Study Mode while this was running: undo.
      await _guard('restore Do Not Disturb', _bridge.exitDnd);
      return;
    }
    state = StudyModeState(
      active: true,
      dndApplied: applied,
      notice: applied
          ? null
          : 'Do Not Disturb is not on: allow access in Study Mode settings.',
    );
  }

  Future<void> _guard(String what, Future<void> Function() op) async {
    try {
      await op();
    } catch (error) {
      debugPrint('Could not $what: $error');
    }
  }
}

/// Keeps the session notification in step with the timer. Watched by the
/// app shell so it runs on every screen.
final sessionNotificationSyncProvider = Provider<void>((ref) {
  final bridge = ref.watch(studyModeBridgeProvider);
  final enabled = ref.watch(
    studyModePrefsProvider.select((p) => p.value?.sessionNotification ?? true),
  );
  String? lastKey;

  void push(StudyTimerState timer) {
    final show = enabled && timer.hasSession;
    final key = show
        ? '${timer.sessionId}|${timer.isRunning}|${timer.mode.name}|'
              '${timer.segmentStartedAtMs}|${timer.countdownEndAtMs}|'
              '${timer.accumulatedSeconds}|${timer.subject}'
        : 'none';
    if (key == lastKey) return;
    lastKey = key;
    final call = show
        ? bridge.showNotification(timer.toMap())
        : bridge.cancelNotification();
    call.catchError((Object error) {
      debugPrint('Session notification update failed: $error');
    });
  }

  ref.listen(
    studyTimerProvider,
    (_, next) => push(next),
    fireImmediately: true,
  );
});

/// Handles Pause / Resume / Finish from the session notification.
class StudyNotificationActions {
  StudyNotificationActions(this._ref);

  final Ref _ref;

  /// Set by the app shell to show the timer after a Finish.
  void Function() onFinished = () {};

  Future<void> handle(String action) async {
    final timer = _ref.read(studyTimerProvider.notifier);
    await timer.ready;
    final state = _ref.read(studyTimerProvider);
    switch (action) {
      case 'pause':
        timer.pause();
      case 'resume':
        if (state.hasSession && !state.isRunning) timer.startOrResume();
      case 'finish':
        if (state.hasSession) {
          try {
            await timer.finish();
          } catch (error) {
            debugPrint('Finish from notification failed: $error');
          }
        }
        onFinished();
      default:
        debugPrint('Unknown notification action: $action');
    }
  }

  /// Delivers an action that launched the app (e.g. tapping Finish).
  Future<void> handlePending() async {
    try {
      final action = await _ref
          .read(studyModeBridgeProvider)
          .takePendingAction();
      if (action != null) await handle(action);
    } catch (error) {
      debugPrint('Could not read pending notification action: $error');
    }
  }
}

/// Registers the notification-action handler once, app-wide.
final studyNotificationActionsProvider = Provider<StudyNotificationActions>((
  ref,
) {
  final actions = StudyNotificationActions(ref);
  ref
      .read(studyModeBridgeProvider)
      .onNotificationAction((action) => unawaited(actions.handle(action)));
  return actions;
});
