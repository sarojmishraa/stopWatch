import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/sessions/data/session_repository.dart';
import '../features/sessions/domain/study_session.dart';
import 'persistence/study_database.dart';
import 'time/study_calendar.dart';

/// Wall clock. Tests override it to control time.
final clockProvider = Provider<Clock>((ref) => DateTime.now);

final studyCalendarProvider = Provider<StudyCalendar>(
  (ref) => StudyCalendar.kolkata(),
);

final studyDatabaseProvider = Provider<StudyDatabase>((ref) => StudyDatabase());

final sessionRepositoryProvider = Provider<SessionRepository>(
  (ref) => SessionRepository(
    ref.watch(studyDatabaseProvider),
    ref.watch(studyCalendarProvider),
    clock: ref.watch(clockProvider),
  ),
);

/// Today/week/month totals. Invalidated whenever sessions change.
final studySummaryProvider = FutureProvider<StudySummary>(
  (ref) => ref.watch(sessionRepositoryProvider).summary(),
);

/// Emits once a second so clocks on screen repaint. Display only: timing
/// is always computed from the persisted timestamps.
final secondTickerProvider = StreamProvider<int>((ref) {
  final clock = ref.watch(clockProvider);
  return Stream.periodic(
    const Duration(seconds: 1),
    (_) => clock().millisecondsSinceEpoch,
  );
});
