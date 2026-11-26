import 'package:eagle_study/features/alarms/data/alarm_bridge.dart';
import 'package:eagle_study/features/alarms/presentation/alarms_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_env.dart';
import '../../support/widget_helpers.dart';

void main() {
  testWidgets('explains missing permissions and creates an alarm', (
    tester,
  ) async {
    usePhoneScreen(tester);
    final env = (await tester.runAsync(TestEnv.create))!;
    env.alarms.permissionsToReturn = const AlarmPermissions(
      notifications: true,
      exactAlarms: false,
      fullScreen: true,
      batteryUnrestricted: true,
      microphone: false,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: env.overrides,
        child: const MaterialApp(home: AlarmsScreen()),
      ),
    );
    await settle(tester);

    expect(find.text('Exact alarms are off'), findsOneWidget);
    expect(find.text('Notifications are off'), findsNothing);
    await tester.tap(find.text('OPEN SETTINGS'));
    await settle(tester);
    expect(env.alarms.calls, contains('openExactAlarmSettings'));

    expect(
      find.text('No alarms yet. Tap NEW ALARM to add one.'),
      findsOneWidget,
    );
    await tester.tap(find.text('NEW ALARM'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'DSA revision');
    await tester.ensureVisible(find.text('SAVE'));
    await tester.tap(find.text('SAVE'));
    await settle(tester);
    await tester.pumpAndSettle();

    expect(find.text('07:00'), findsOneWidget);
    expect(find.text('Weekdays · Classic alarm'), findsOneWidget);
    expect(find.text('DSA revision'), findsOneWidget);
    expect(env.alarms.synced.single['message'], 'DSA revision');
    await disposeTree(tester);
  });
}
