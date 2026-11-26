import 'package:flutter/services.dart';

/// Dart side of android/.../study/StudyModeChannel.kt.
abstract class StudyModeBridge {
  /// Shows/updates the session notification from the persisted timer map.
  Future<void> showNotification(Map<String, Object?> timerState);
  Future<void> cancelNotification();

  /// Whether the user granted Do Not Disturb (notification policy) access.
  Future<bool> dndAccess();
  Future<void> openDndSettings();

  /// "alarms" or "priority". Returns false without access.
  Future<bool> enterDnd(String mode);

  /// Restores the previous filter: "restored", "kept_user_change",
  /// "no_access" or "inactive".
  Future<String> exitDnd();

  /// True if Study Mode changed DND and has not restored it yet.
  Future<bool> dndActive();

  Future<void> setKeepScreenOn(bool on);

  /// Action from a notification that launched the app ("finish"), if any.
  Future<String?> takePendingAction();

  /// Pause/Resume taps while the app is running.
  void onNotificationAction(void Function(String action) handler);
}

class MethodChannelStudyModeBridge implements StudyModeBridge {
  static const _channel = MethodChannel('eagle_study/study_mode');

  @override
  Future<void> showNotification(Map<String, Object?> timerState) =>
      _channel.invokeMethod('showNotification', timerState);

  @override
  Future<void> cancelNotification() =>
      _channel.invokeMethod('cancelNotification');

  @override
  Future<bool> dndAccess() async =>
      await _channel.invokeMethod<bool>('dndAccess') ?? false;

  @override
  Future<void> openDndSettings() => _channel.invokeMethod('openDndSettings');

  @override
  Future<bool> enterDnd(String mode) async =>
      await _channel.invokeMethod<bool>('enterDnd', {'mode': mode}) ?? false;

  @override
  Future<String> exitDnd() async =>
      await _channel.invokeMethod<String>('exitDnd') ?? 'inactive';

  @override
  Future<bool> dndActive() async =>
      await _channel.invokeMethod<bool>('dndActive') ?? false;

  @override
  Future<void> setKeepScreenOn(bool on) =>
      _channel.invokeMethod('setKeepScreenOn', {'on': on});

  @override
  Future<String?> takePendingAction() =>
      _channel.invokeMethod<String>('takePendingAction');

  @override
  void onNotificationAction(void Function(String action) handler) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'notificationAction') {
        handler(call.arguments as String);
      }
    });
  }
}
