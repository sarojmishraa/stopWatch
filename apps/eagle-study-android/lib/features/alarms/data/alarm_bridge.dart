import 'package:flutter/services.dart';

/// What Android currently allows the app to do. Each flag maps to a
/// permission the user can grant or revoke in system settings.
class AlarmPermissions {
  const AlarmPermissions({
    required this.notifications,
    required this.exactAlarms,
    required this.fullScreen,
    required this.batteryUnrestricted,
    required this.microphone,
  });

  static const unknown = AlarmPermissions(
    notifications: true,
    exactAlarms: true,
    fullScreen: true,
    batteryUnrestricted: true,
    microphone: false,
  );

  /// POST_NOTIFICATIONS (Android 13+): without it alarms ring silently in
  /// the background with no way to dismiss them from the shade.
  final bool notifications;

  /// SCHEDULE_EXACT_ALARM (Android 12+): without it alarms may be late.
  final bool exactAlarms;

  /// USE_FULL_SCREEN_INTENT (Android 14+): the alarm screen over the lock
  /// screen. Without it only a heads-up notification appears.
  final bool fullScreen;

  /// Exempt from battery optimisation. Some manufacturers delay or drop
  /// alarms for optimised apps.
  final bool batteryUnrestricted;

  /// RECORD_AUDIO, only needed to record a custom alarm voice.
  final bool microphone;

  bool get allCritical => notifications && exactAlarms;

  factory AlarmPermissions.fromMap(Map<Object?, Object?> m) => AlarmPermissions(
    notifications: m['notifications'] == true,
    exactAlarms: m['exactAlarms'] == true,
    fullScreen: m['fullScreen'] == true,
    batteryUnrestricted: m['batteryUnrestricted'] == true,
    microphone: m['microphone'] == true,
  );
}

/// The Dart side of the native alarm engine (android/.../alarm/AlarmChannel.kt).
abstract class AlarmBridge {
  /// Replaces the native schedule with [alarms] (enabled ones only).
  Future<void> sync(List<Map<String, Object?>> alarms);

  /// Rings when a focus countdown ends, even if the app is closed.
  Future<void> scheduleTimerEnd({
    required DateTime at,
    required String message,
    required String sound,
  });

  Future<void> cancelTimerEnd();

  /// IDs of one-time alarms that rang since the last call.
  Future<List<String>> consumeFiredOneShots();

  Future<AlarmPermissions> permissions();
  Future<void> requestNotifications();
  Future<void> requestMicrophone();
  Future<void> openExactAlarmSettings();
  Future<void> openFullScreenSettings();
  Future<void> openBatterySettings();

  Future<void> preview(Map<String, Object?> alarm);
  Future<void> stopPreview();

  /// Starts recording; returns the file path being written.
  Future<String> startRecording();
  Future<void> stopRecording();
  Future<void> deleteRecording(String path);
}

class MethodChannelAlarmBridge implements AlarmBridge {
  static const _channel = MethodChannel('eagle_study/alarms');

  @override
  Future<void> sync(List<Map<String, Object?>> alarms) =>
      _channel.invokeMethod('sync', {'alarms': alarms});

  @override
  Future<void> scheduleTimerEnd({
    required DateTime at,
    required String message,
    required String sound,
  }) => _channel.invokeMethod('scheduleTimerEnd', {
    'atMillis': at.millisecondsSinceEpoch,
    'message': message,
    'sound': sound,
  });

  @override
  Future<void> cancelTimerEnd() => _channel.invokeMethod('cancelTimerEnd');

  @override
  Future<List<String>> consumeFiredOneShots() async =>
      (await _channel.invokeListMethod<String>('consumeFiredOneShots')) ?? [];

  @override
  Future<AlarmPermissions> permissions() async => AlarmPermissions.fromMap(
    (await _channel.invokeMapMethod<Object?, Object?>('permissions')) ?? {},
  );

  @override
  Future<void> requestNotifications() =>
      _channel.invokeMethod('requestNotifications');

  @override
  Future<void> requestMicrophone() =>
      _channel.invokeMethod('requestMicrophone');

  @override
  Future<void> openExactAlarmSettings() =>
      _channel.invokeMethod('openExactAlarmSettings');

  @override
  Future<void> openFullScreenSettings() =>
      _channel.invokeMethod('openFullScreenSettings');

  @override
  Future<void> openBatterySettings() =>
      _channel.invokeMethod('openBatterySettings');

  @override
  Future<void> preview(Map<String, Object?> alarm) =>
      _channel.invokeMethod('preview', alarm);

  @override
  Future<void> stopPreview() => _channel.invokeMethod('stopPreview');

  @override
  Future<String> startRecording() async =>
      (await _channel.invokeMethod<String>('startRecording'))!;

  @override
  Future<void> stopRecording() => _channel.invokeMethod('stopRecording');

  @override
  Future<void> deleteRecording(String path) =>
      _channel.invokeMethod('deleteRecording', {'path': path});
}
