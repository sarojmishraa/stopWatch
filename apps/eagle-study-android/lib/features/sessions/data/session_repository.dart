import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../core/persistence/study_database.dart';
import '../../../core/time/study_calendar.dart';
import '../domain/study_session.dart';

class InvalidSessionException implements Exception {
  InvalidSessionException(this.problems);
  final List<String> problems;

  @override
  String toString() => 'Invalid study session: ${problems.join(' ')}';
}

/// Study sessions on the device. Every change is written together with a
/// `sync_outbox` entry in one transaction, so nothing saved offline can be
/// missed by the uploader.
class SessionRepository {
  SessionRepository(this._database, this._calendar, {Clock? clock})
    : _clock = clock ?? DateTime.now;

  static const _entity = 'study_session';

  final StudyDatabase _database;
  final StudyCalendar _calendar;
  final Clock _clock;

  Future<String> deviceId() async =>
      StudyDatabase.deviceIdFor(await _database.database);

  /// Saves a finished session and clears the persisted running timer in the
  /// same transaction, so a crash can neither lose the session nor let the
  /// recovered timer save it twice. Saving an ID that already exists is a
  /// no-op (returns false), which makes retries safe.
  Future<bool> completeSession(StudySessionRecord record) async {
    final problems = record.validate();
    if (problems.isNotEmpty) throw InvalidSessionException(problems);
    final db = await _database.database;
    return db.transaction((txn) async {
      final inserted = await txn.insert(
        'study_sessions',
        _toRow(record),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      await txn.delete('app_state', where: 'key = ?', whereArgs: ['timer']);
      if (inserted == 0) return false;
      await _enqueuePut(txn, record);
      return true;
    });
  }

  /// Edits the user-editable fields of a session.
  Future<StudySessionRecord> updateDetails(
    String id, {
    required String? subject,
    required String? notes,
  }) async {
    final db = await _database.database;
    return db.transaction((txn) async {
      final current = await _find(txn, id);
      if (current == null || current.isDeleted) {
        throw StateError('Session $id no longer exists.');
      }
      final cleanSubject = _blankToNull(subject);
      final cleanNotes = _blankToNull(notes);
      final updated = current.copyWith(
        subject: cleanSubject,
        clearSubject: cleanSubject == null,
        notes: cleanNotes,
        clearNotes: cleanNotes == null,
        clientUpdatedAt: _clock(),
      );
      final problems = updated.validate();
      if (problems.isNotEmpty) throw InvalidSessionException(problems);
      await txn.update(
        'study_sessions',
        _toRow(updated),
        where: 'id = ?',
        whereArgs: [id],
      );
      await _enqueuePut(txn, updated);
      return updated;
    });
  }

  /// Soft-deletes so the deletion can be synced; idempotent.
  Future<void> delete(String id) async {
    final db = await _database.database;
    await db.transaction((txn) async {
      final current = await _find(txn, id);
      if (current == null || current.isDeleted) return;
      final now = _clock().millisecondsSinceEpoch;
      await txn.update(
        'study_sessions',
        {'deleted_at': now, 'client_updated_at': now},
        where: 'id = ?',
        whereArgs: [id],
      );
      await _enqueue(txn, id, 'delete', null);
    });
  }

  /// Live sessions, newest first. Pass the last item's [startedAt] as
  /// [before] to load the next page.
  Future<List<StudySessionRecord>> history({
    int limit = 50,
    DateTime? before,
  }) async {
    final db = await _database.database;
    final rows = await db.query(
      'study_sessions',
      where: before == null
          ? 'deleted_at IS NULL'
          : 'deleted_at IS NULL AND started_at < ?',
      whereArgs: before == null ? null : [before.millisecondsSinceEpoch],
      orderBy: 'started_at DESC, id',
      limit: limit,
    );
    return rows.map(_fromRow).toList();
  }

  /// Totals in the study timezone. A session counts toward the local day,
  /// week (Monday start) and month in which it started, like the API does.
  Future<StudySummary> summary() async {
    final db = await _database.database;
    final now = _clock();
    final day = _calendar.startOfDay(now).millisecondsSinceEpoch;
    final week = _calendar.startOfWeek(now).millisecondsSinceEpoch;
    final month = _calendar.startOfMonth(now).millisecondsSinceEpoch;
    final totals = (await db.rawQuery(
      'SELECT '
      'COALESCE(SUM(CASE WHEN started_at >= ? THEN duration_seconds END), 0) AS today, '
      'COALESCE(SUM(CASE WHEN started_at >= ? THEN duration_seconds END), 0) AS week, '
      'COALESCE(SUM(CASE WHEN started_at >= ? THEN duration_seconds END), 0) AS month, '
      'COUNT(CASE WHEN started_at >= ? THEN 1 END) AS today_sessions, '
      'COUNT(*) AS total_sessions '
      'FROM study_sessions WHERE deleted_at IS NULL',
      [day, week, month, day],
    )).single;
    final pending =
        (await db.rawQuery('SELECT COUNT(*) AS n FROM sync_outbox'))
                .single['n']!
            as int;
    return StudySummary(
      todaySeconds: totals['today']! as int,
      weekSeconds: totals['week']! as int,
      monthSeconds: totals['month']! as int,
      todaySessions: totals['today_sessions']! as int,
      totalSessions: totals['total_sessions']! as int,
      dailyTargetMinutes: StudySummary.defaultDailyTargetMinutes,
      weeklyTargetMinutes: StudySummary.defaultWeeklyTargetMinutes,
      recent: await history(limit: 4),
      pendingSync: pending,
    );
  }

  Future<StudySessionRecord?> _find(DatabaseExecutor db, String id) async {
    final rows = await db.query(
      'study_sessions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.single);
  }

  Future<void> _enqueuePut(DatabaseExecutor db, StudySessionRecord record) =>
      _enqueue(db, record.id, 'put', jsonEncode(record.toApiJson()));

  Future<void> _enqueue(
    DatabaseExecutor db,
    String id,
    String operation,
    String? payload,
  ) async {
    await db.insert('sync_outbox', {
      'entity': _entity,
      'entity_id': id,
      'operation': operation,
      'payload': payload,
      'enqueued_at': _clock().millisecondsSinceEpoch,
      'attempts': 0,
      'last_error': null,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static Map<String, Object?> _toRow(StudySessionRecord r) => {
    'id': r.id,
    'mode': r.mode.name,
    'started_at': r.startedAt.millisecondsSinceEpoch,
    'ended_at': r.endedAt.millisecondsSinceEpoch,
    'duration_seconds': r.durationSeconds,
    'planned_seconds': r.plannedSeconds,
    'subject': r.subject,
    'notes': r.notes,
    'laps': jsonEncode(r.lapsSeconds),
    'source_device': r.sourceDevice,
    'client_updated_at': r.clientUpdatedAt.millisecondsSinceEpoch,
    'deleted_at': r.deletedAt?.millisecondsSinceEpoch,
  };

  static StudySessionRecord _fromRow(Map<String, Object?> row) {
    DateTime at(String key) =>
        DateTime.fromMillisecondsSinceEpoch(row[key]! as int, isUtc: true);
    final deleted = row['deleted_at'] as int?;
    return StudySessionRecord(
      id: row['id']! as String,
      mode: SessionMode.values.byName(row['mode']! as String),
      startedAt: at('started_at'),
      endedAt: at('ended_at'),
      durationSeconds: row['duration_seconds']! as int,
      plannedSeconds: row['planned_seconds'] as int?,
      subject: row['subject'] as String?,
      notes: row['notes'] as String?,
      lapsSeconds: (jsonDecode(row['laps']! as String) as List<dynamic>)
          .cast<int>(),
      sourceDevice: row['source_device']! as String,
      clientUpdatedAt: at('client_updated_at'),
      deletedAt: deleted == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(deleted, isUtc: true),
    );
  }
}
