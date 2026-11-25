import 'package:eagle_study/core/persistence/study_database.dart';
import 'package:eagle_study/features/dashboard/presentation/dashboard_screen.dart';
import 'package:eagle_study/features/timer/application/study_timer_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory stand-in for the sqflite database so widget tests exercise the
/// real controller and UI without touching platform storage.
class _InMemoryStudyDatabase extends StudyDatabase {
  Map<String, Object?>? timerState;
  final sessions = <StudySession>[];

  @override
  Future<Map<String, dynamic>?> loadTimerState() async =>
      timerState == null ? null : Map<String, dynamic>.from(timerState!);

  @override
  Future<void> saveTimerState(Map<String, Object?> state) async =>
      timerState = state;

  @override
  Future<void> clearTimerState() async => timerState = null;

  @override
  Future<void> saveSession({
    required DateTime startedAt,
    required int durationSeconds,
  }) async {
    if (durationSeconds <= 0) return;
    sessions.add(
      StudySession(startedAt: startedAt, durationSeconds: durationSeconds),
    );
  }

  @override
  Future<StudySummary> loadSummary({DateTime? now}) async => StudySummary(
    todaySeconds: sessions.fold(0, (sum, s) => sum + s.durationSeconds),
    weekSeconds: sessions.fold(0, (sum, s) => sum + s.durationSeconds),
    sessionCount: sessions.length,
    recentSessions: sessions.reversed.take(4).toList(),
  );
}

void main() {
  testWidgets('starting the stopwatch persists a running, timestamp-anchored '
      'state and reveals Study Mode', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final database = _InMemoryStudyDatabase();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [studyDatabaseProvider.overrideWithValue(database)],
        child: const MaterialApp(home: DashboardScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('RESET'), findsOneWidget);
    expect(find.text('LAP'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();

    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    expect(find.text('OPEN DISTRACTION-FREE STUDY MODE'), findsOneWidget);
    expect(database.timerState?['isRunning'], isTrue);
    expect(database.timerState?['segmentStartedAtMs'], isA<int>());
    expect(database.timerState?['sessionStartedAtMs'], isA<int>());

    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.pump();
    expect(database.timerState?['isRunning'], isFalse);
    expect(database.timerState?['segmentStartedAtMs'], isNull);

    // Unmount so the controller's ticker is cancelled via ref.onDispose.
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
