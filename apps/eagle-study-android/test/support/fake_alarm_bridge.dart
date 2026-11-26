import 'package:eagle_study/features/alarms/data/alarm_bridge.dart';

/// Records what the app asks the native alarm engine to do. The native side
/// itself is covered by JVM tests (android/app/src/test) and needs a device
/// for end-to-end checks.
class FakeAlarmBridge implements AlarmBridge {
  List<Map<String, Object?>> synced = [];
  int syncCalls = 0;
  ({DateTime at, String message, String sound})? timerEnd;
  int timerCancels = 0;
  List<String> firedOneShots = [];
  AlarmPermissions permissionsToReturn = const AlarmPermissions(
    notifications: true,
    exactAlarms: true,
    fullScreen: true,
    batteryUnrestricted: true,
    microphone: true,
  );
  final calls = <String>[];

  @override
  Future<void> sync(List<Map<String, Object?>> alarms) async {
    syncCalls++;
    synced = alarms;
  }

  @override
  Future<void> scheduleTimerEnd({
    required DateTime at,
    required String message,
    required String sound,
  }) async => timerEnd = (at: at, message: message, sound: sound);

  @override
  Future<void> cancelTimerEnd() async {
    timerCancels++;
    timerEnd = null;
  }

  @override
  Future<List<String>> consumeFiredOneShots() async {
    final fired = firedOneShots;
    firedOneShots = [];
    return fired;
  }

  @override
  Future<AlarmPermissions> permissions() async => permissionsToReturn;

  @override
  Future<void> requestNotifications() async =>
      calls.add('requestNotifications');
  @override
  Future<void> requestMicrophone() async => calls.add('requestMicrophone');
  @override
  Future<void> openExactAlarmSettings() async =>
      calls.add('openExactAlarmSettings');
  @override
  Future<void> openFullScreenSettings() async =>
      calls.add('openFullScreenSettings');
  @override
  Future<void> openBatterySettings() async => calls.add('openBatterySettings');
  @override
  Future<void> preview(Map<String, Object?> alarm) async =>
      calls.add('preview');
  @override
  Future<void> stopPreview() async => calls.add('stopPreview');
  @override
  Future<String> startRecording() async => '/fake/recording.m4a';
  @override
  Future<void> stopRecording() async => calls.add('stopRecording');
  @override
  Future<void> deleteRecording(String path) async => calls.add('delete:$path');
}
