import 'package:eagle_study/features/study/data/study_mode_bridge.dart';

/// Records Study Mode calls. Native behaviour (DND restore rule, timer
/// math for notification buttons) is covered by JVM tests.
class FakeStudyModeBridge implements StudyModeBridge {
  bool access = false;
  bool dndOn = false;
  bool keepScreenOn = false;
  Map<String, Object?>? notification;
  String? pendingAction;
  void Function(String action)? actionHandler;
  final calls = <String>[];

  @override
  Future<void> showNotification(Map<String, Object?> timerState) async {
    calls.add('show');
    notification = timerState;
  }

  @override
  Future<void> cancelNotification() async {
    calls.add('cancel');
    notification = null;
  }

  @override
  Future<bool> dndAccess() async => access;

  @override
  Future<void> openDndSettings() async => calls.add('openDndSettings');

  @override
  Future<bool> enterDnd(String mode) async {
    calls.add('enterDnd:$mode');
    if (!access) return false;
    dndOn = true;
    return true;
  }

  @override
  Future<String> exitDnd() async {
    calls.add('exitDnd');
    if (!dndOn) return 'inactive';
    dndOn = false;
    return 'restored';
  }

  @override
  Future<bool> dndActive() async => dndOn;

  @override
  Future<void> setKeepScreenOn(bool on) async => keepScreenOn = on;

  @override
  Future<String?> takePendingAction() async {
    final action = pendingAction;
    pendingAction = null;
    return action;
  }

  @override
  void onNotificationAction(void Function(String action) handler) =>
      actionHandler = handler;
}
