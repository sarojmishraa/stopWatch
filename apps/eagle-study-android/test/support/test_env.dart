import 'dart:io';

import 'package:eagle_study/core/persistence/study_database.dart';
import 'package:eagle_study/core/providers.dart';
import 'package:eagle_study/features/alarms/application/alarm_controller.dart';
import 'package:eagle_study/features/study/application/study_mode_controller.dart';
import 'package:eagle_study/core/time/study_calendar.dart';
import 'package:eagle_study/features/sessions/data/session_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fake_alarm_bridge.dart';
import 'fake_study_mode_bridge.dart';

/// A clock tests move by hand.
class FakeClock {
  FakeClock(this.now);
  DateTime now;
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}

/// 2026-12-01 10:00 in Asia/Kolkata (Tuesday of the plan's first week).
final planWeekOneTuesday = DateTime.utc(2026, 12, 1, 4, 30);

/// Real SQLite (via FFI) in a temp file, so tests exercise the same schema,
/// constraints and migrations as the app on a phone.
class TestEnv {
  TestEnv._(this.dbPath, this.clock) : database = _open(dbPath);

  static Future<TestEnv> create({DateTime? now}) async {
    sqfliteFfiInit();
    initializeTimeZones();
    final dir = await Directory.systemTemp.createTemp('eagle_study_test');
    addTearDown(() => dir.delete(recursive: true));
    final env = TestEnv._(
      '${dir.path}/eagle.db',
      FakeClock(now ?? planWeekOneTuesday),
    );
    // Open eagerly, in the real async zone. If a widget test opened it lazily
    // inside its fake-async zone, closing it in tearDown would wait forever.
    await env.db;
    addTearDown(env.close);
    return env;
  }

  final String dbPath;
  final FakeClock clock;
  final alarms = FakeAlarmBridge();
  final studyMode = FakeStudyModeBridge();
  StudyDatabase database;

  static StudyDatabase _open(String path) =>
      StudyDatabase(factory: databaseFactoryFfi, path: path);

  final calendar = StudyCalendar.kolkata();

  SessionRepository get repository =>
      SessionRepository(database, calendar, clock: clock.call);

  Future<Database> get db => database.database;

  List<Override> get overrides => [
    clockProvider.overrideWithValue(clock.call),
    studyDatabaseProvider.overrideWithValue(database),
    alarmBridgeProvider.overrideWithValue(alarms),
    studyModeBridgeProvider.overrideWithValue(studyMode),
  ];

  ProviderContainer container() {
    final container = ProviderContainer(overrides: overrides);
    addTearDown(container.dispose);
    return container;
  }

  /// Simulates the process being killed: closes the connection and opens a
  /// fresh one on the same file.
  Future<void> restartProcess() async {
    await close();
    database = _open(dbPath);
  }

  Future<void> close() async => (await database.database).close();

  Future<int> count(String table, [String? where]) async {
    final rows = await (await db).rawQuery(
      'SELECT COUNT(*) AS n FROM $table${where == null ? '' : ' WHERE $where'}',
    );
    return rows.single['n']! as int;
  }
}
