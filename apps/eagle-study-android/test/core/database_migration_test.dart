import 'dart:io';

import 'package:eagle_study/core/persistence/study_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('upgrading from v2 moves legacy sessions into the v3 table and '
      'queues them for sync', () async {
    final dir = await Directory.systemTemp.createTemp('eagle_migration');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/eagle.db';

    // Recreate the session part of the v2 schema exactly as the old app did.
    final v2 = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE sessions (id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'started_at INTEGER NOT NULL, duration_seconds INTEGER NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE app_state (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
        },
      ),
    );
    final start = DateTime.utc(2026, 11, 20, 2).millisecondsSinceEpoch;
    await v2.insert('sessions', {
      'started_at': start,
      'duration_seconds': 1500,
    });
    await v2.insert('sessions', {'started_at': start, 'duration_seconds': 0});
    await v2.close();

    final database = StudyDatabase(factory: databaseFactoryFfi, path: path);
    final db = await database.database;
    addTearDown(db.close);

    expect(await db.getVersion(), StudyDatabase.schemaVersion);
    final rows = await db.query('study_sessions');
    expect(rows, hasLength(1), reason: 'zero-length legacy rows are dropped');
    final row = rows.single;
    expect(row['id'], matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(row['started_at'], start);
    expect(row['ended_at'], start + 1500 * 1000);
    expect(row['duration_seconds'], 1500);
    expect(row['source_device'], startsWith('android-'));

    final outbox = await db.query('sync_outbox');
    expect(outbox.single['entity_id'], row['id']);
    final legacy = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE name = 'sessions'",
    );
    expect(legacy, isEmpty);
    expect(await db.query('alarms'), isEmpty, reason: 'v4 alarms table exists');
  });

  test('the database enforces session invariants, not just the app', () async {
    final dir = await Directory.systemTemp.createTemp('eagle_constraints');
    addTearDown(() => dir.delete(recursive: true));
    final database = StudyDatabase(
      factory: databaseFactoryFfi,
      path: '${dir.path}/eagle.db',
    );
    final db = await database.database;
    addTearDown(db.close);

    Future<void> insert(int durationSeconds, int spanSeconds) =>
        db.insert('study_sessions', {
          'id': 'id-$durationSeconds-$spanSeconds',
          'mode': 'stopwatch',
          'started_at': 0,
          'ended_at': spanSeconds * 1000,
          'duration_seconds': durationSeconds,
          'source_device': 'android-test',
          'client_updated_at': 0,
        });

    await insert(600, 900);
    await expectLater(insert(1800, 900), throwsA(isA<DatabaseException>()));
    await expectLater(insert(0, 900), throwsA(isA<DatabaseException>()));
  });
}
