import 'dart:convert';

import 'package:eagle_study/features/sessions/data/session_repository.dart';
import 'package:eagle_study/features/sessions/domain/study_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import '../../support/test_env.dart';

StudySessionRecord session(
  DateTime start,
  int seconds, {
  String? subject,
  String? id,
}) => StudySessionRecord(
  id: id ?? const Uuid().v4(),
  mode: SessionMode.stopwatch,
  startedAt: start,
  endedAt: start.add(Duration(seconds: seconds)),
  durationSeconds: seconds,
  subject: subject,
  sourceDevice: 'android-test',
  clientUpdatedAt: start.add(Duration(seconds: seconds)),
);

void main() {
  late TestEnv env;
  late SessionRepository repo;

  setUp(() async {
    env = await TestEnv.create();
    repo = env.repository;
  });

  test('completing a session stores it, queues it for sync and clears '
      'the persisted timer in one step', () async {
    await env.database.saveTimerState({'isRunning': true});
    final s = session(DateTime.utc(2026, 12, 1, 3), 1500, subject: 'Java');

    expect(await repo.completeSession(s), isTrue);

    expect(await env.count('study_sessions'), 1);
    expect(await env.database.loadTimerState(), isNull);
    final outbox = await (await env.db).query('sync_outbox');
    expect(outbox, hasLength(1));
    expect(outbox.single['operation'], 'put');
    expect(jsonDecode(outbox.single['payload']! as String), s.toApiJson());
  });

  test('saving the same session ID twice is a no-op', () async {
    final s = session(DateTime.utc(2026, 12, 1, 3), 600);
    expect(await repo.completeSession(s), isTrue);
    expect(await repo.completeSession(s), isFalse);
    expect(await env.count('study_sessions'), 1);
    expect(await env.count('sync_outbox'), 1);
  });

  test('invalid sessions are rejected before anything is written', () async {
    final bad = StudySessionRecord(
      id: const Uuid().v4(),
      mode: SessionMode.stopwatch,
      startedAt: DateTime.utc(2026, 12, 1, 3),
      endedAt: DateTime.utc(2026, 12, 1, 3, 5),
      durationSeconds: 3600, // more focus than wall time
      sourceDevice: 'android-test',
      clientUpdatedAt: DateTime.utc(2026, 12, 1, 3, 5),
    );
    await expectLater(
      repo.completeSession(bad),
      throwsA(isA<InvalidSessionException>()),
    );
    expect(await env.count('study_sessions'), 0);
    expect(await env.count('sync_outbox'), 0);
  });

  test(
    'editing replaces the pending sync entry with a newer version',
    () async {
      final s = session(DateTime.utc(2026, 12, 1, 3), 600);
      await repo.completeSession(s);
      env.clock.advance(const Duration(minutes: 5));

      final updated = await repo.updateDetails(
        s.id,
        subject: '  Go ',
        notes: 'Channels and select',
      );

      expect(updated.subject, 'Go');
      expect(updated.clientUpdatedAt.isAfter(s.clientUpdatedAt), isTrue);
      final outbox = await (await env.db).query('sync_outbox');
      expect(outbox, hasLength(1), reason: 'one pending op per record');
      final payload = jsonDecode(outbox.single['payload']! as String) as Map;
      expect(payload['subject'], 'Go');
      expect(payload['notes'], 'Channels and select');
    },
  );

  test('delete is soft, idempotent, queued, and hidden from totals', () async {
    final s = session(DateTime.utc(2026, 12, 1, 3), 600);
    await repo.completeSession(s);

    await repo.delete(s.id);
    await repo.delete(s.id);

    expect(await env.count('study_sessions', 'deleted_at IS NOT NULL'), 1);
    final outbox = await (await env.db).query('sync_outbox');
    expect(outbox.single['operation'], 'delete');
    expect(await repo.history(), isEmpty);
    expect((await repo.summary()).totalSessions, 0);
  });

  test(
    'summary uses Asia/Kolkata day, Monday week and month boundaries',
    () async {
      // Clock: Tue 1 Dec 2026, 10:00 IST.
      await repo.completeSession(
        session(DateTime.utc(2026, 11, 30, 18, 45), 1800),
      ); // 00:15 IST 1 Dec
      await repo.completeSession(
        session(DateTime.utc(2026, 11, 30, 18, 15), 600),
      ); // 23:45 IST 30 Nov (Mon)
      await repo.completeSession(
        session(DateTime.utc(2026, 11, 29, 10), 300),
      ); // Sun 29 Nov

      final summary = await repo.summary();

      expect(summary.todaySeconds, 1800);
      expect(summary.weekSeconds, 2400);
      expect(summary.monthSeconds, 1800);
      expect(summary.todaySessions, 1);
      expect(summary.totalSessions, 3);
      expect(summary.pendingSync, 3);
      expect(
        summary.recent.first.startedAt,
        DateTime.utc(2026, 11, 30, 18, 45),
      );
    },
  );

  test('history is newest first and pages without gaps or repeats', () async {
    final starts = List.generate(5, (i) => DateTime.utc(2026, 11, 25 + i, 3));
    for (final start in starts) {
      await repo.completeSession(session(start, 600));
    }
    final first = await repo.history(limit: 2);
    final second = await repo.history(limit: 2, before: first.last.startedAt);
    final third = await repo.history(limit: 2, before: second.last.startedAt);

    final seen = [
      ...first,
      ...second,
      ...third,
    ].map((s) => s.startedAt).toList();
    expect(seen, starts.reversed.toList());
  });
}
