import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../data/alarm_bridge.dart';
import '../data/alarm_repository.dart';
import '../domain/alarm.dart';

final alarmBridgeProvider = Provider<AlarmBridge>(
  (ref) => MethodChannelAlarmBridge(),
);

final alarmRepositoryProvider = Provider<AlarmRepository>(
  (ref) => AlarmRepository(ref.watch(studyDatabaseProvider)),
);

/// Re-read when the app resumes: the user may have changed permissions in
/// system settings.
final alarmPermissionsProvider = FutureProvider<AlarmPermissions>((ref) async {
  try {
    return await ref.watch(alarmBridgeProvider).permissions();
  } catch (error) {
    debugPrint('Alarm permissions unavailable: $error');
    return AlarmPermissions.unknown;
  }
});

final alarmControllerProvider =
    AsyncNotifierProvider<AlarmController, List<Alarm>>(AlarmController.new);

/// The next enabled alarm and when it rings, for the dashboard.
final nextAlarmProvider = Provider<({Alarm alarm, DateTime at})?>((ref) {
  ref.watch(secondTickerProvider); // roll over once an alarm time passes
  final alarms = ref.watch(alarmControllerProvider).value ?? const [];
  final now = ref.read(clockProvider)();
  final calendar = ref.watch(studyCalendarProvider);
  ({Alarm alarm, DateTime at})? next;
  for (final alarm in alarms.where((a) => a.enabled)) {
    final at = nextTrigger(alarm, now, calendar);
    if (next == null || at.isBefore(next.at)) next = (alarm: alarm, at: at);
  }
  return next;
});

class AlarmController extends AsyncNotifier<List<Alarm>> {
  AlarmRepository get _repository => ref.read(alarmRepositoryProvider);
  AlarmBridge get _bridge => ref.read(alarmBridgeProvider);

  @override
  Future<List<Alarm>> build() async {
    // One-time alarms that rang while the app was closed are now off.
    try {
      await _repository.disable(await _bridge.consumeFiredOneShots());
    } catch (error) {
      debugPrint('Could not read fired alarms: $error');
    }
    final alarms = await _repository.all();
    try {
      await _sync(alarms);
    } catch (error) {
      debugPrint('Could not schedule alarms: $error');
    }
    return alarms;
  }

  /// Saves (creates or updates) and reschedules. Throws
  /// [InvalidAlarmException] or a platform error the UI should show.
  Future<void> save(Alarm alarm) async {
    await _repository.save(alarm);
    await _reloadAndSync();
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final alarm = (state.value ?? await _repository.all()).firstWhere(
      (a) => a.id == id,
    );
    await save(alarm.copyWith(enabled: enabled));
  }

  Future<void> delete(String id) async {
    final alarm = (state.value ?? const <Alarm>[])
        .where((a) => a.id == id)
        .firstOrNull;
    await _repository.delete(id);
    await _reloadAndSync();
    final path = alarm?.recordingPath;
    if (path != null) {
      unawaited(_bridge.deleteRecording(path).catchError((_) {}));
    }
  }

  /// Picks up one-time alarms that rang while the app was in the background.
  Future<void> refreshFired() async {
    final fired = await _bridge.consumeFiredOneShots();
    if (fired.isEmpty) return;
    await _repository.disable(fired);
    state = AsyncData(await _repository.all());
  }

  Future<void> _reloadAndSync() async {
    final alarms = await _repository.all();
    state = AsyncData(alarms);
    await _sync(alarms);
  }

  Future<void> _sync(List<Alarm> alarms) {
    final zone = ref.read(studyCalendarProvider).zoneName;
    return _bridge.sync([
      for (final alarm in alarms.where((a) => a.enabled)) alarm.toNative(zone),
    ]);
  }
}
