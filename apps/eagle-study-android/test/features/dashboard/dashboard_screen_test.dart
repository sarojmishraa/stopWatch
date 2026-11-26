import 'package:eagle_study/features/dashboard/presentation/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_env.dart';
import '../../support/widget_helpers.dart';

void main() {
  Future<TestEnv> pumpDashboard(WidgetTester tester) async {
    usePhoneScreen(tester);
    final env = (await tester.runAsync(TestEnv.create))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: env.overrides,
        child: const MaterialApp(home: DashboardScreen()),
      ),
    );
    await settle(tester);
    return env;
  }

  testWidgets('a stopwatch session is saved and shows up in today’s totals', (
    tester,
  ) async {
    final env = await pumpDashboard(tester);

    await tester.ensureVisible(find.text('Java'));
    await tester.tap(find.text('Java'));
    await tester.ensureVisible(find.byIcon(Icons.play_arrow_rounded));
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await settle(tester);
    expect(find.text('SESSION IN PROGRESS'), findsOneWidget);
    expect(find.text('LAP'), findsOneWidget);

    env.clock.advance(const Duration(minutes: 25));
    await tester.ensureVisible(find.byIcon(Icons.pause_rounded));
    await tester.tap(find.byIcon(Icons.pause_rounded));
    await settle(tester);
    expect(find.text('PAUSED'), findsOneWidget);

    await tester.ensureVisible(find.text('FINISH'));
    await tester.tap(find.text('FINISH'));
    await settle(tester);

    expect(find.text('Session saved: 25m.'), findsOneWidget);
    expect(find.text('READY WHEN YOU ARE'), findsOneWidget);
    expect(find.text('25m'), findsWidgets); // today + week metrics
    expect(find.widgetWithText(Row, 'Java'), findsWidgets);
    expect(
      find.text('Saved on this device · 1 change waiting to sync'),
      findsOneWidget,
    );
    expect((await tester.runAsync(env.repository.history))!, hasLength(1));
    await disposeTree(tester);
  });

  testWidgets('presets and custom duration set the focus timer; over 24 h '
      'is refused', (tester) async {
    await pumpDashboard(tester);

    await tester.ensureVisible(find.text('FOCUS TIMER'));
    await tester.tap(find.text('FOCUS TIMER'));
    await settle(tester);
    expect(find.text('25:00'), findsOneWidget);

    await tester.ensureVisible(find.text('45m'));
    await tester.tap(find.text('45m'));
    await settle(tester);
    expect(find.text('45:00'), findsOneWidget);

    await tester.ensureVisible(find.text('CUSTOM HOURS / MINUTES / SECONDS'));
    await tester.tap(find.text('CUSTOM HOURS / MINUTES / SECONDS'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Hours'), '24');
    await tester.enterText(find.widgetWithText(TextFormField, 'Minutes'), '1');
    await tester.tap(find.text('SET TIMER'));
    await tester.pump();
    expect(find.text('A session can be at most 24 hours.'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Hours'), '1');
    await tester.enterText(find.widgetWithText(TextFormField, 'Minutes'), '30');
    await tester.tap(find.text('SET TIMER'));
    await tester.pumpAndSettle();
    await settle(tester);
    expect(find.text('01:30:00'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('reset asks before discarding more than a minute of focus', (
    tester,
  ) async {
    final env = await pumpDashboard(tester);
    await tester.ensureVisible(find.byIcon(Icons.play_arrow_rounded));
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await settle(tester);
    env.clock.advance(const Duration(minutes: 2));

    await tester.ensureVisible(find.text('RESET'));
    await tester.tap(find.text('RESET'));
    await tester.pumpAndSettle();
    expect(find.text('Discard this session?'), findsOneWidget);
    await tester.tap(find.text('KEEP GOING'));
    await tester.pumpAndSettle();
    expect(find.text('SESSION IN PROGRESS'), findsOneWidget);

    await tester.ensureVisible(find.text('RESET'));
    await tester.tap(find.text('RESET'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DISCARD'));
    await settle(tester);
    expect(find.text('READY WHEN YOU ARE'), findsOneWidget);
    expect((await tester.runAsync(env.repository.history))!, isEmpty);
    await disposeTree(tester);
  });
}
