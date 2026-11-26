import 'dart:convert';
import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../../../core/config/api_config.dart';
import '../../../core/persistence/study_database.dart';
import '../../auth/data/neon_auth_client.dart';
import '../../sessions/domain/study_session.dart';

class SyncResult {
  const SyncResult({
    required this.pushed,
    required this.pulled,
    required this.pending,
    this.syncedAt,
  });

  final int pushed;
  final int pulled;
  final int pending;
  final DateTime? syncedAt;
}

class SyncException implements Exception {
  SyncException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Synchronizes local `study_sessions` and `sync_outbox` with the Go +
/// PostgreSQL backend (`/v1/study-sessions` and `/v1/sync/study-sessions`).
class SyncRepository {
  SyncRepository(
    this._database,
    this._auth, {
    String? baseUrl,
    HttpClient Function()? httpClientFactory,
  }) : _baseUrl = (baseUrl ?? ApiConfig.apiBaseUrl).replaceAll(
         RegExp(r'/+$'),
         '',
       ),
       _httpClientFactory = httpClientFactory ?? HttpClient.new;

  static const _cursorKey = 'sync_cursor';
  static const _lastSyncKey = 'last_sync_at';

  final StudyDatabase _database;
  final NeonAuthClient _auth;
  final String _baseUrl;
  final HttpClient Function() _httpClientFactory;

  Future<int> pendingCount() async {
    final db = await _database.database;
    return (await db.rawQuery('SELECT COUNT(*) AS n FROM sync_outbox'))
            .single['n']!
        as int;
  }

  Future<DateTime?> lastSyncedAt() async {
    final raw = await _readState(_lastSyncKey);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> resetCursor() async {
    final db = await _database.database;
    await db.delete(
      'app_state',
      where: 'key IN (?, ?)',
      whereArgs: [_cursorKey, _lastSyncKey],
    );
  }

  /// Pushes all pending outbox items and pulls any newer changes from Postgres.
  /// Returns `null` if the user is not signed in.
  Future<SyncResult?> syncNow() async {
    var token = await _auth.getValidToken();
    if (token == null) return null;

    var pushed = 0;
    final db = await _database.database;

    // 1. Push local outbox in FIFO order.
    final outbox = await db.query('sync_outbox', orderBy: 'enqueued_at ASC');
    for (final item in outbox) {
      final entityId = item['entity_id']! as String;
      final operation = item['operation']! as String;
      final payload = item['payload'] as String?;

      final result = await _pushItem(
        entityId: entityId,
        operation: operation,
        payload: payload,
        token: token!,
        onRefreshToken: () async {
          token = await _auth.getValidToken(forceRefresh: true);
          return token;
        },
      );

      if (result.done) {
        if (result.serverSession != null) {
          await _upsertServerSession(db, result.serverSession!);
        }
        await db.delete(
          'sync_outbox',
          where: 'entity = ? AND entity_id = ?',
          whereArgs: ['study_session', entityId],
        );
        pushed++;
      } else if (result.error != null) {
        await db.update(
          'sync_outbox',
          {
            'attempts': ((item['attempts'] as int?) ?? 0) + 1,
            'last_error': result.error,
          },
          where: 'entity = ? AND entity_id = ?',
          whereArgs: ['study_session', entityId],
        );
      }
    }

    // 2. Pull remote changes since last cursor.
    var cursor = int.tryParse((await _readState(_cursorKey)) ?? '0') ?? 0;
    var pulled = 0;
    var hasMore = true;

    while (hasMore) {
      final res = await _authorizedRequest(
        'GET',
        '$_baseUrl/v1/sync/study-sessions?since=$cursor&limit=500',
        token: token!,
        onRefreshToken: () async {
          token = await _auth.getValidToken(forceRefresh: true);
          return token;
        },
      );
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw SyncException(
          _extractProblem(res.body, 'Sync pull failed (${res.statusCode}).'),
        );
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final changes = (body['changes'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>();
      if (changes.isNotEmpty) {
        await db.transaction((txn) async {
          for (final raw in changes) {
            final record = StudySessionRecord.fromApiJson(raw);
            await _upsertServerSession(txn, record);
          }
        });
        pulled += changes.length;
      }
      final nextCursor = (body['nextCursor'] as num?)?.toInt() ?? cursor;
      hasMore = body['hasMore'] == true;
      if (nextCursor > cursor) {
        cursor = nextCursor;
        await _writeState(_cursorKey, cursor.toString());
      }
    }

    final now = DateTime.now().toUtc();
    await _writeState(_lastSyncKey, now.toIso8601String());
    return SyncResult(
      pushed: pushed,
      pulled: pulled,
      pending: await pendingCount(),
      syncedAt: now,
    );
  }

  Future<_PushOutcome> _pushItem({
    required String entityId,
    required String operation,
    required String? payload,
    required String token,
    required Future<String?> Function() onRefreshToken,
  }) async {
    final url = '$_baseUrl/v1/study-sessions/$entityId';
    if (operation == 'delete') {
      final res = await _authorizedRequest(
        'DELETE',
        url,
        token: token,
        onRefreshToken: onRefreshToken,
      );
      if (res.statusCode == 204 || res.statusCode == 404) {
        return const _PushOutcome(done: true);
      }
      if (res.statusCode >= 500 || res.statusCode == 429) {
        throw SyncException('Server busy (${res.statusCode}).');
      }
      return _PushOutcome(
        done: false,
        error: _extractProblem(res.body, 'Delete failed (${res.statusCode}).'),
      );
    }

    if (payload == null) {
      return const _PushOutcome(done: true);
    }
    final res = await _authorizedRequest(
      'PUT',
      url,
      token: token,
      rawBody: payload,
      onRefreshToken: onRefreshToken,
    );
    if (res.statusCode == 200 || res.statusCode == 201) {
      return const _PushOutcome(done: true);
    }
    if (res.statusCode == 409) {
      // Server holds a newer or deleted version; reconcile local copy.
      final data = _tryDecodeMap(res.body);
      final current = data?['current'];
      if (current is Map<String, dynamic>) {
        return _PushOutcome(
          done: true,
          serverSession: StudySessionRecord.fromApiJson(current),
        );
      }
      return _PushOutcome(
        done: false,
        error: _extractProblem(res.body, 'Conflict (409).'),
      );
    }
    if (res.statusCode >= 500 || res.statusCode == 429) {
      throw SyncException('Server busy (${res.statusCode}).');
    }
    return _PushOutcome(
      done: false,
      error: _extractProblem(res.body, 'Upload failed (${res.statusCode}).'),
    );
  }

  Future<void> _upsertServerSession(
    DatabaseExecutor db,
    StudySessionRecord r,
  ) async {
    await db.insert('study_sessions', {
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
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<_ApiResponse> _authorizedRequest(
    String method,
    String url, {
    required String token,
    String? rawBody,
    required Future<String?> Function() onRefreshToken,
  }) async {
    var res = await _send(method, url, token: token, rawBody: rawBody);
    if (res.statusCode == 401) {
      final refreshed = await onRefreshToken();
      if (refreshed == null) {
        throw AuthException('Please sign in again.');
      }
      res = await _send(method, url, token: refreshed, rawBody: rawBody);
    }
    return res;
  }

  Future<_ApiResponse> _send(
    String method,
    String url, {
    required String token,
    String? rawBody,
  }) async {
    final client = _httpClientFactory()
      ..connectionTimeout = const Duration(seconds: 30);
    try {
      final req = await client.openUrl(method, Uri.parse(url));
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (rawBody != null) {
        req.headers.contentType = ContentType.json;
        req.write(rawBody);
      }
      // Render free tier can take ~20-30s on cold start.
      final res = await req.close().timeout(const Duration(seconds: 45));
      final body = await res.transform(utf8.decoder).join();
      return _ApiResponse(statusCode: res.statusCode, body: body);
    } on SocketException {
      throw SyncException('No internet connection.');
    } finally {
      client.close();
    }
  }

  Future<String?> _readState(String key) async {
    final db = await _database.database;
    final rows = await db.query(
      'app_state',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['value'] as String?;
  }

  Future<void> _writeState(String key, String value) async {
    final db = await _database.database;
    await db.insert('app_state', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Map<String, dynamic>? _tryDecodeMap(String raw) {
    if (raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static String _extractProblem(String raw, String fallback) {
    final map = _tryDecodeMap(raw);
    if (map == null) return fallback;
    final detail = map['detail'] ?? map['title'] ?? map['message'];
    return detail is String && detail.trim().isNotEmpty
        ? detail.trim()
        : fallback;
  }
}

class _PushOutcome {
  const _PushOutcome({required this.done, this.serverSession, this.error});

  final bool done;
  final StudySessionRecord? serverSession;
  final String? error;
}

class _ApiResponse {
  const _ApiResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}
