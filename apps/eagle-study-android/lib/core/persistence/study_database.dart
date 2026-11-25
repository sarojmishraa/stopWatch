import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

class RoadmapMilestone {
  const RoadmapMilestone({
    required this.id,
    required this.month,
    required this.title,
    required this.startDate,
    required this.endDate,
    required this.description,
    required this.skills,
    required this.completion,
    required this.isSample,
  });

  final String id;
  final int month;
  final String title;
  final DateTime startDate;
  final DateTime endDate;
  final String description;
  final List<String> skills;
  final int completion;
  final bool isSample;
}

class ScheduledStudyTask {
  const ScheduledStudyTask({
    required this.id,
    required this.milestoneId,
    required this.date,
    required this.startTime,
    required this.subject,
    required this.topic,
    required this.durationMinutes,
    required this.task,
    required this.isComplete,
    required this.isSample,
  });

  final int id;
  final String milestoneId;
  final DateTime date;
  final String startTime;
  final String subject;
  final String topic;
  final int durationMinutes;
  final String task;
  final bool isComplete;
  final bool isSample;
}

/// Owns the on-device SQLite database: schema, migrations and seed data.
///
/// Tests pass a `sqflite_common_ffi` factory and an in-memory path so they run
/// against real SQLite with the same migrations as the app.
class StudyDatabase {
  StudyDatabase({DatabaseFactory? factory, String? path})
    : _factory = factory, // ignore: prefer_initializing_formals
      _path = path; // ignore: prefer_initializing_formals

  static const schemaVersion = 3;

  final DatabaseFactory? _factory;
  final String? _path;
  Future<Database>? _opening;

  /// The open database, shared by every repository.
  Future<Database> get database => _opening ??= _open();

  Future<Database> get _db => database;

  Future<Database> _open() async {
    final factory = _factory ?? databaseFactory;
    final dbPath =
        _path ?? path.join(await factory.getDatabasesPath(), 'eagle_study.db');
    return factory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE app_state (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
          await _createLearningTables(db);
          await _seedLearningPlan(db);
          await createSessionTables(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await _createLearningTables(db);
            await _seedLearningPlan(db);
          }
          if (oldVersion < 3) {
            await createSessionTables(db);
            await _migrateLegacySessions(db);
          }
        },
      ),
    );
  }

  /// Schema v3: sessions keyed by client UUID plus a sync outbox. Constraints
  /// mirror the PostgreSQL schema so invalid rows are rejected on-device.
  static Future<void> createSessionTables(DatabaseExecutor db) async {
    await db.execute(
      'CREATE TABLE study_sessions ('
      'id TEXT PRIMARY KEY, '
      "mode TEXT NOT NULL CHECK (mode IN ('stopwatch', 'countdown', 'pomodoro')), "
      'started_at INTEGER NOT NULL, '
      'ended_at INTEGER NOT NULL, '
      'duration_seconds INTEGER NOT NULL CHECK (duration_seconds BETWEEN 1 AND 86400), '
      'planned_seconds INTEGER CHECK (planned_seconds IS NULL OR planned_seconds BETWEEN 1 AND 86400), '
      'subject TEXT CHECK (subject IS NULL OR length(subject) <= 120), '
      'notes TEXT CHECK (notes IS NULL OR length(notes) <= 4000), '
      "laps TEXT NOT NULL DEFAULT '[]', "
      'source_device TEXT NOT NULL, '
      'client_updated_at INTEGER NOT NULL, '
      'deleted_at INTEGER, '
      'CHECK (ended_at >= started_at), '
      'CHECK (duration_seconds * 1000 <= ended_at - started_at + 1000))',
    );
    await db.execute(
      'CREATE INDEX study_sessions_started_idx '
      'ON study_sessions (started_at DESC) WHERE deleted_at IS NULL',
    );
    // One pending operation per record: a newer edit replaces the older one.
    await db.execute(
      'CREATE TABLE sync_outbox ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, '
      'entity TEXT NOT NULL, '
      'entity_id TEXT NOT NULL, '
      "operation TEXT NOT NULL CHECK (operation IN ('put', 'delete')), "
      'payload TEXT, '
      'enqueued_at INTEGER NOT NULL, '
      'attempts INTEGER NOT NULL DEFAULT 0, '
      'last_error TEXT, '
      'UNIQUE (entity, entity_id))',
    );
  }

  /// Moves v2 `sessions` rows (integer id, start + duration only) into
  /// `study_sessions` with fresh UUIDs, and queues each one for sync.
  /// Legacy rows did not record their mode, so they are stored as stopwatch.
  Future<void> _migrateLegacySessions(DatabaseExecutor db) async {
    final exists = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'sessions'",
    );
    if (exists.isEmpty) return;
    final deviceId = await deviceIdFor(db);
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = await db.query('sessions', orderBy: 'started_at');
    for (final row in rows) {
      final startedAt = row['started_at']! as int;
      final duration = row['duration_seconds']! as int;
      if (duration <= 0) continue;
      final id = const Uuid().v4();
      final record = <String, Object?>{
        'id': id,
        'mode': 'stopwatch',
        'started_at': startedAt,
        'ended_at': startedAt + duration * 1000,
        'duration_seconds': duration.clamp(1, 86400),
        'laps': '[]',
        'source_device': deviceId,
        'client_updated_at': now,
      };
      await db.insert('study_sessions', record);
      await db.insert('sync_outbox', {
        'entity': 'study_session',
        'entity_id': id,
        'operation': 'put',
        'enqueued_at': now,
      });
    }
    await db.execute('DROP TABLE sessions');
  }

  /// Stable per-install identifier sent as `sourceDevice`.
  static Future<String> deviceIdFor(DatabaseExecutor db) async {
    final rows = await db.query(
      'app_state',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['device_id'],
    );
    if (rows.isNotEmpty) return rows.single['value']! as String;
    final id = 'android-${const Uuid().v4()}';
    await db.insert('app_state', {'key': 'device_id', 'value': id});
    return id;
  }

  Future<void> _createLearningTables(DatabaseExecutor db) async {
    await db.execute(
      'CREATE TABLE roadmap_milestones ('
      'id TEXT PRIMARY KEY, month INTEGER NOT NULL, title TEXT NOT NULL, '
      'start_date TEXT NOT NULL, end_date TEXT NOT NULL, description TEXT NOT NULL, '
      'skills TEXT NOT NULL, completion INTEGER NOT NULL DEFAULT 0, '
      'is_sample INTEGER NOT NULL DEFAULT 1)',
    );
    await db.execute(
      'CREATE TABLE study_tasks ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, milestone_id TEXT NOT NULL, '
      'date TEXT NOT NULL, start_time TEXT NOT NULL, subject TEXT NOT NULL, '
      'topic TEXT NOT NULL, duration_minutes INTEGER NOT NULL, task TEXT NOT NULL, '
      'is_complete INTEGER NOT NULL DEFAULT 0, is_sample INTEGER NOT NULL DEFAULT 1, '
      'FOREIGN KEY(milestone_id) REFERENCES roadmap_milestones(id))',
    );
    await db.execute(
      'CREATE INDEX study_tasks_date_index ON study_tasks(date, start_time)',
    );
  }

  Future<void> _seedLearningPlan(DatabaseExecutor db) async {
    final existing = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM roadmap_milestones',
    );
    if ((existing.single['count']! as int) > 0) return;

    final milestones = <RoadmapMilestone>[
      _milestone(
        'm01',
        1,
        'Java Foundations',
        '2026-11-30',
        '2026-12-27',
        'Build fluency in modern Java, object-oriented design, collections and testing.',
        ['Java 21', 'OOP', 'Collections', 'JUnit'],
      ),
      _milestone(
        'm02',
        2,
        'Advanced Java & Concurrency',
        '2026-12-28',
        '2027-01-24',
        'Understand JVM behavior, concurrency primitives and reliable asynchronous code.',
        ['JVM', 'Threads', 'Executors', 'Concurrency'],
      ),
      _milestone(
        'm03',
        3,
        'Spring Backend Engineering',
        '2027-01-25',
        '2027-02-21',
        'Create production-style APIs with Spring Boot, persistence and observability.',
        ['Spring Boot', 'REST', 'PostgreSQL', 'Testing'],
      ),
      _milestone(
        'm04',
        4,
        'Go Backend Foundations',
        '2027-02-22',
        '2027-03-21',
        'Write idiomatic Go services and learn its concurrency and error-handling model.',
        ['Go', 'HTTP', 'Goroutines', 'Context'],
      ),
      _milestone(
        'm05',
        5,
        'Production APIs & Data',
        '2027-03-22',
        '2027-04-18',
        'Design robust service boundaries, data models and API contracts.',
        ['API design', 'SQL', 'Redis', 'OpenAPI'],
      ),
      _milestone(
        'm06',
        6,
        'Linux, Networking & Reliability',
        '2027-04-19',
        '2027-05-16',
        'Build operational fluency in Linux, networks, metrics and incident response.',
        ['Linux', 'TCP/IP', 'Metrics', 'SLOs'],
      ),
      _milestone(
        'm07',
        7,
        'Containers & Kubernetes',
        '2027-05-17',
        '2027-06-13',
        'Package, deploy and operate services using containers and Kubernetes.',
        ['Docker', 'Kubernetes', 'Helm', 'CI/CD'],
      ),
      _milestone(
        'm08',
        8,
        'Distributed Systems Core',
        '2027-06-14',
        '2027-07-11',
        'Study replication, consistency, partitioning and failure models.',
        ['Replication', 'Consistency', 'CAP', 'Consensus'],
      ),
      _milestone(
        'm09',
        9,
        'Messaging & Event-Driven Systems',
        '2027-07-12',
        '2027-08-08',
        'Build event-driven workflows and reason about delivery guarantees.',
        ['Kafka', 'Outbox', 'Idempotency', 'Sagas'],
      ),
      _milestone(
        'm10',
        10,
        'Platform Engineering Projects',
        '2027-08-09',
        '2027-09-05',
        'Deliver a deployable platform project with developer-facing interfaces.',
        ['Platform APIs', 'Terraform', 'GitOps', 'Security'],
      ),
      _milestone(
        'm11',
        11,
        'System Design & Interview Practice',
        '2027-09-06',
        '2027-10-03',
        'Practice clear system design, DSA problem solving and technical communication.',
        ['System design', 'DSA', 'Trade-offs', 'Communication'],
      ),
      _milestone(
        'm12',
        12,
        'Portfolio & International Job Search',
        '2027-10-04',
        '2027-11-28',
        'Polish project evidence, prepare applications and rehearse interviews.',
        ['Portfolio', 'Resume', 'Interviews', 'Applications'],
      ),
    ];
    final batch = db.batch();
    for (final item in milestones) {
      batch.insert('roadmap_milestones', {
        'id': item.id,
        'month': item.month,
        'title': item.title,
        'start_date': _dateKey(item.startDate),
        'end_date': _dateKey(item.endDate),
        'description': item.description,
        'skills': jsonEncode(item.skills),
        'completion': 0,
        'is_sample': 1,
      });
    }

    final start = DateTime(2026, 11, 30);
    final end = DateTime(2027, 11, 28);
    var day = start;
    while (!day.isAfter(end)) {
      final milestone = milestones.firstWhere(
        (item) => !day.isBefore(item.startDate) && !day.isAfter(item.endDate),
      );
      final weekday = day.weekday < DateTime.saturday;
      final sessions = weekday
          ? [
              (
                '07:00',
                120,
                'Deep work',
                'Study the core concept and write concise notes.',
              ),
              (
                '22:00',
                240,
                'Practice lab',
                'Implement, test and review a small learning task.',
              ),
            ]
          : [
              (
                '09:00',
                300,
                'Build session',
                'Work through a guided project milestone.',
              ),
              (
                '16:00',
                300,
                'Review & practice',
                'Solve exercises and record learning reflections.',
              ),
            ];
      for (final session in sessions) {
        batch.insert('study_tasks', {
          'milestone_id': milestone.id,
          'date': _dateKey(day),
          'start_time': session.$1,
          'subject': _subjectForMonth(milestone.month),
          'topic': milestone.title,
          'duration_minutes': session.$2,
          'task': session.$3,
          'is_complete': 0,
          'is_sample': 1,
        });
      }
      day = day.add(const Duration(days: 1));
    }
    await batch.commit(noResult: true);
  }

  RoadmapMilestone _milestone(
    String id,
    int month,
    String title,
    String start,
    String end,
    String description,
    List<String> skills,
  ) {
    return RoadmapMilestone(
      id: id,
      month: month,
      title: title,
      startDate: DateTime.parse(start),
      endDate: DateTime.parse(end),
      description: description,
      skills: skills,
      completion: 0,
      isSample: true,
    );
  }

  String _subjectForMonth(int month) => switch (month) {
    1 || 2 || 3 => 'Java',
    4 || 5 => 'Go',
    6 || 7 || 10 => 'Platform Engineering',
    8 || 9 => 'Distributed Systems',
    11 => 'DSA & System Design',
    _ => 'International Job Preparation',
  };

  String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<List<RoadmapMilestone>> loadMilestones() async {
    final rows = await (await _db).query(
      'roadmap_milestones',
      orderBy: 'month',
    );
    return rows.map((row) {
      return RoadmapMilestone(
        id: row['id']! as String,
        month: row['month']! as int,
        title: row['title']! as String,
        startDate: DateTime.parse(row['start_date']! as String),
        endDate: DateTime.parse(row['end_date']! as String),
        description: row['description']! as String,
        skills: (jsonDecode(row['skills']! as String) as List<dynamic>)
            .cast<String>(),
        completion: row['completion']! as int,
        isSample: (row['is_sample']! as int) == 1,
      );
    }).toList();
  }

  Future<List<ScheduledStudyTask>> loadTasks(DateTime date) async {
    final key = _dateKey(date);
    final rows = await (await _db).query(
      'study_tasks',
      where: 'date = ?',
      whereArgs: [key],
      orderBy: 'start_time',
    );
    return rows.map(_taskFromRow).toList();
  }

  Future<List<ScheduledStudyTask>> loadTasksBetween(
    DateTime start,
    DateTime end,
  ) async {
    final rows = await (await _db).query(
      'study_tasks',
      where: 'date >= ? AND date <= ?',
      whereArgs: [_dateKey(start), _dateKey(end)],
      orderBy: 'date, start_time',
    );
    return rows.map(_taskFromRow).toList();
  }

  ScheduledStudyTask _taskFromRow(Map<String, Object?> row) {
    return ScheduledStudyTask(
      id: row['id']! as int,
      milestoneId: row['milestone_id']! as String,
      date: DateTime.parse(row['date']! as String),
      startTime: row['start_time']! as String,
      subject: row['subject']! as String,
      topic: row['topic']! as String,
      durationMinutes: row['duration_minutes']! as int,
      task: row['task']! as String,
      isComplete: (row['is_complete']! as int) == 1,
      isSample: (row['is_sample']! as int) == 1,
    );
  }

  Future<void> updateTaskCompletion(int id, bool isComplete) async {
    final db = await _db;
    await db.transaction((transaction) async {
      final taskRows = await transaction.query(
        'study_tasks',
        columns: ['milestone_id'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (taskRows.isEmpty) return;
      final milestoneId = taskRows.single['milestone_id']! as String;
      await transaction.update(
        'study_tasks',
        {'is_complete': isComplete ? 1 : 0, 'is_sample': 0},
        where: 'id = ?',
        whereArgs: [id],
      );
      final count = await transaction.rawQuery(
        'SELECT COUNT(*) AS total, SUM(is_complete) AS complete '
        'FROM study_tasks WHERE milestone_id = ?',
        [milestoneId],
      );
      final total = count.single['total']! as int;
      final complete = count.single['complete'] as int? ?? 0;
      await transaction.update(
        'roadmap_milestones',
        {
          'completion': total == 0 ? 0 : (complete * 100 / total).round(),
          'is_sample': 0,
        },
        where: 'id = ?',
        whereArgs: [milestoneId],
      );
    });
  }

  Future<void> rescheduleTask(int id, DateTime date) async {
    await (await _db).update(
      'study_tasks',
      {'date': _dateKey(date), 'is_sample': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateTask({
    required int id,
    required String startTime,
    required int durationMinutes,
    required String task,
    required String subject,
    required String topic,
  }) async {
    await (await _db).update(
      'study_tasks',
      {
        'start_time': startTime,
        'duration_minutes': durationMinutes,
        'task': task,
        'subject': subject,
        'topic': topic,
        'is_sample': 0,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> addTask({
    required String milestoneId,
    required DateTime date,
    required String startTime,
    required String subject,
    required String topic,
    required int durationMinutes,
    required String task,
  }) async {
    await (await _db).insert('study_tasks', {
      'milestone_id': milestoneId,
      'date': _dateKey(date),
      'start_time': startTime,
      'subject': subject,
      'topic': topic,
      'duration_minutes': durationMinutes,
      'task': task,
      'is_complete': 0,
      'is_sample': 0,
    });
  }

  Future<void> updateMilestoneCompletion(String id, int completion) async {
    await (await _db).update(
      'roadmap_milestones',
      {'completion': completion.clamp(0, 100), 'is_sample': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<Map<String, dynamic>?> loadTimerState() async {
    final rows = await (await _db).query(
      'app_state',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['timer'],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return jsonDecode(rows.single['value']! as String) as Map<String, dynamic>;
  }

  Future<void> saveTimerState(Map<String, Object?> state) async {
    await (await _db).insert('app_state', {
      'key': 'timer',
      'value': jsonEncode(state),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> clearTimerState() async {
    await (await _db).delete(
      'app_state',
      where: 'key = ?',
      whereArgs: ['timer'],
    );
  }
}
