import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../core/persistence/study_database.dart';
import '../domain/alarm.dart';

class InvalidAlarmException implements Exception {
  InvalidAlarmException(this.problems);
  final List<String> problems;

  @override
  String toString() => problems.join(' ');
}

/// Alarms stored on the device (source of truth for the native schedule).
class AlarmRepository {
  AlarmRepository(this._database);

  final StudyDatabase _database;

  static const _timerSoundKey = 'timer_alarm_sound';

  Future<List<Alarm>> all() async {
    final rows = await (await _database.database).query(
      'alarms',
      orderBy: 'hour, minute, created_at',
    );
    return rows.map(_fromRow).toList();
  }

  Future<void> save(Alarm alarm) async {
    final problems = alarm.validate();
    if (problems.isNotEmpty) throw InvalidAlarmException(problems);
    final db = await _database.database;
    final existing = await db.query(
      'alarms',
      columns: ['created_at'],
      where: 'id = ?',
      whereArgs: [alarm.id],
    );
    await db.insert('alarms', {
      ..._toRow(alarm),
      'created_at': existing.isEmpty
          ? DateTime.now().millisecondsSinceEpoch
          : existing.single['created_at'],
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> delete(String id) async {
    await (await _database.database).delete(
      'alarms',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Turns off one-time alarms that have already rung.
  Future<void> disable(Iterable<String> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    await (await _database.database).update(
      'alarms',
      {'enabled': 0},
      where: 'id IN (${List.filled(list.length, '?').join(', ')})',
      whereArgs: list,
    );
  }

  /// Sound used when a focus countdown ends.
  Future<AlarmSound> timerSound() async {
    final rows = await (await _database.database).query(
      'app_state',
      where: 'key = ?',
      whereArgs: [_timerSoundKey],
    );
    return AlarmSound.parse(
      rows.isEmpty ? null : rows.single['value'] as String,
    );
  }

  Future<void> setTimerSound(AlarmSound sound) async {
    if (sound == AlarmSound.recording) {
      throw InvalidAlarmException(['Recordings can only be used by alarms.']);
    }
    await (await _database.database).insert('app_state', {
      'key': _timerSoundKey,
      'value': sound.name,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Map<String, Object?> _toRow(Alarm a) => {
    'id': a.id,
    'hour': a.hour,
    'minute': a.minute,
    'days': jsonEncode(a.days.toList()..sort()),
    'message': a.message.trim(),
    'sound': a.sound.name,
    'volume': a.volume,
    'vibrate': a.vibrate ? 1 : 0,
    'enabled': a.enabled ? 1 : 0,
    'recording_path': a.recordingPath,
  };

  static Alarm _fromRow(Map<String, Object?> r) => Alarm(
    id: r['id']! as String,
    hour: r['hour']! as int,
    minute: r['minute']! as int,
    days: (jsonDecode(r['days']! as String) as List<dynamic>)
        .cast<int>()
        .toSet(),
    message: r['message']! as String,
    sound: AlarmSound.parse(r['sound'] as String?),
    volume: (r['volume']! as num).toDouble(),
    vibrate: r['vibrate'] == 1,
    enabled: r['enabled'] == 1,
    recordingPath: r['recording_path'] as String?,
  );
}
