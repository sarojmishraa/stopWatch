import 'package:eagle_study/features/sessions/domain/study_session.dart';
import 'package:eagle_study/features/sessions/presentation/history_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_env.dart';
import '../../support/widget_helpers.dart';

StudySessionRecord _session(
  String id,
  DateTime start,
  int seconds,
  String subject,
) => StudySessionRecord(
  id: id,
  mode: SessionMode.stopwatch,
  startedAt: start,
  endedAt: start.add(Duration(seconds: seconds)),
  durationSeconds: seconds,
  subject: subject,
  lapsSeconds: [seconds ~/ 2],
  sourceDevice: 'android-test',
  clientUpdatedAt: start.add(Duration(seconds: seconds)),
);

void main() {
  testWidgets('history groups sessions by IST day and deletes after confirm', (
    tester,
  ) async {
    usePhoneScreen(tester);
    final env = (await tester.runAsync(TestEnv.create))!;
    await tester.runAsync(() async {
      // 08:00 IST and 07:30 IST on Tue 1 Dec 2026.
      await env.repository.completeSession(
        _session(
          '11111111-1111-4111-8111-111111111111',
          DateTime.utc(2026, 12, 1, 2, 30),
          3600,
          'Java',
        ),
      );
      await env.repository.completeSession(
        _session(
          '22222222-2222-4222-8222-222222222222',
          DateTime.utc(2026, 12, 1, 2),
          900,
          'DSA',
        ),
      );
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: env.overrides,
        child: const MaterialApp(home: HistoryScreen()),
      ),
    );
    await settle(tester);

    expect(find.text('TUE, 1 DEC 2026'), findsOneWidget);
    expect(find.text('1h 15m'), findsOneWidget); // day total
    expect(find.text('Java'), findsOneWidget);
    expect(find.text('08:00 – 09:00 · 1 lap'), findsOneWidget);

    await tester.tap(find.text('Java'));
    await tester.pumpAndSettle();
    expect(find.text('LAPS'), findsOneWidget);

    await tester.tap(find.text('DELETE'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this session?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'DELETE'));
    await settle(tester);
    await tester.pumpAndSettle();

    expect(find.text('Java'), findsNothing);
    expect(find.text('DSA'), findsOneWidget);
    final left = (await tester.runAsync(env.repository.history))!;
    expect(left.map((s) => s.subject), ['DSA']);
    await disposeTree(tester);
  });
}
