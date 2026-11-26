import 'dart:convert';
import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../../../core/config/api_config.dart';
import '../../../core/persistence/study_database.dart';

class AuthException implements Exception {
  AuthException(this.message);
  final String message;

  @override
  String toString() => message;
}

class AuthSession {
  const AuthSession({
    required this.email,
    required this.cookies,
    this.name,
    this.jwt,
    this.jwtExpiresAt,
  });

  final String email;
  final String? name;
  final Map<String, String> cookies;
  final String? jwt;
  final DateTime? jwtExpiresAt;

  bool get hasValidJwt {
    final token = jwt;
    final exp = jwtExpiresAt;
    if (token == null || token.isEmpty || exp == null) return false;
    return exp.isAfter(DateTime.now().toUtc().add(const Duration(seconds: 45)));
  }

  AuthSession copyWith({String? jwt, DateTime? jwtExpiresAt}) {
    return AuthSession(
      email: email,
      name: name,
      cookies: cookies,
      jwt: jwt ?? this.jwt,
      jwtExpiresAt: jwtExpiresAt ?? this.jwtExpiresAt,
    );
  }

  Map<String, Object?> toJson() => {
    'email': email,
    'name': name,
    'cookies': cookies,
    'jwt': jwt,
    'jwtExpiresAt': jwtExpiresAt?.toUtc().toIso8601String(),
  };

  static AuthSession? fromJson(Map<String, dynamic> json) {
    final email = json['email'] as String?;
    final rawCookies = json['cookies'] as Map<String, dynamic>?;
    if (email == null || email.isEmpty || rawCookies == null) return null;
    final expRaw = json['jwtExpiresAt'] as String?;
    return AuthSession(
      email: email,
      name: json['name'] as String?,
      cookies: rawCookies.map((k, v) => MapEntry(k, v.toString())),
      jwt: json['jwt'] as String?,
      jwtExpiresAt: expRaw == null ? null : DateTime.tryParse(expRaw)?.toUtc(),
    );
  }
}

/// Direct HTTP client for Neon Auth (Better Auth) with session persistence in
/// SQLite `app_state`.
class NeonAuthClient {
  NeonAuthClient(
    this._database, {
    String? baseUrl,
    HttpClient Function()? httpClientFactory,
  }) : _baseUrl = (baseUrl ?? ApiConfig.neonAuthBaseUrl).replaceAll(
         RegExp(r'/+$'),
         '',
       ),
       _httpClientFactory = httpClientFactory ?? HttpClient.new;

  static const _stateKey = 'auth_session';

  final StudyDatabase _database;
  final String _baseUrl;
  final HttpClient Function() _httpClientFactory;

  Future<AuthSession?> currentSession() async {
    final db = await _database.database;
    final rows = await db.query(
      'app_state',
      where: 'key = ?',
      whereArgs: [_stateKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final raw = rows.single['value'] as String?;
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return AuthSession.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<AuthSession> signIn({
    required String email,
    required String password,
  }) => _authenticate(
    path: '/sign-in/email',
    body: {'email': email.trim(), 'password': password},
    fallbackEmail: email.trim(),
  );

  Future<AuthSession> signUp({
    required String name,
    required String email,
    required String password,
  }) => _authenticate(
    path: '/sign-up/email',
    body: {'name': name.trim(), 'email': email.trim(), 'password': password},
    fallbackEmail: email.trim(),
    fallbackName: name.trim(),
  );

  Future<void> signOut() async {
    final session = await currentSession();
    final db = await _database.database;
    await db.delete('app_state', where: 'key = ?', whereArgs: [_stateKey]);
    if (session != null && session.cookies.isNotEmpty) {
      try {
        await _request(
          'POST',
          '$_baseUrl/sign-out',
          cookies: session.cookies,
          body: const {},
        );
      } catch (_) {
        // Best-effort remote sign-out; local session is already cleared.
      }
    }
  }

  /// Returns a valid EdDSA JWT for the Go API, refreshing via `/token` if
  /// needed. Returns null if the user is not signed in.
  Future<String?> getValidToken({bool forceRefresh = false}) async {
    final session = await currentSession();
    if (session == null) return null;
    if (!forceRefresh && session.hasValidJwt) {
      return session.jwt;
    }
    if (session.cookies.isEmpty) return null;

    final res = await _request('GET', '$_baseUrl/token', cookies: session.cookies);
    if (res.statusCode == 401 || res.statusCode == 403) {
      await signOut();
      throw AuthException('Session expired. Please sign in again.');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw AuthException(_extractError(res.body, 'Failed to refresh auth token.'));
    }
    final data = _tryDecodeMap(res.body);
    final token = data?['token'] as String? ?? res.headers['set-auth-jwt'];
    if (token == null || token.isEmpty) {
      throw AuthException('Auth server did not return a token.');
    }
    final updated = session.copyWith(
      jwt: token,
      jwtExpiresAt: _decodeJwtExp(token) ??
          DateTime.now().toUtc().add(const Duration(minutes: 10)),
    );
    await _saveSession(updated);
    return token;
  }

  Future<AuthSession> _authenticate({
    required String path,
    required Map<String, Object?> body,
    required String fallbackEmail,
    String? fallbackName,
  }) async {
    final res = await _request('POST', '$_baseUrl$path', body: body);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw AuthException(_extractError(res.body, 'Authentication failed (${res.statusCode}).'));
    }

    final data = _tryDecodeMap(res.body);
    final user = data?['user'] as Map<String, dynamic>?;
    final email = (user?['email'] as String?) ?? fallbackEmail;
    final name = (user?['name'] as String?) ?? fallbackName;

    var jwt = res.headers['set-auth-jwt'] ?? data?['token'] as String?;
    // Better Auth may return an opaque session token in `data['token']`;
    // only treat it as a JWT if it has 3 dot-separated segments.
    if (jwt != null && jwt.split('.').length != 3) {
      jwt = null;
    }

    var session = AuthSession(
      email: email,
      name: name,
      cookies: res.cookies,
      jwt: jwt,
      jwtExpiresAt: jwt == null ? null : _decodeJwtExp(jwt),
    );
    await _saveSession(session);

    if (session.jwt == null) {
      final fetched = await getValidToken(forceRefresh: true);
      session = session.copyWith(
        jwt: fetched,
        jwtExpiresAt: fetched == null ? null : _decodeJwtExp(fetched),
      );
    }
    return session;
  }

  Future<void> _saveSession(AuthSession session) async {
    final db = await _database.database;
    await db.insert('app_state', {
      'key': _stateKey,
      'value': jsonEncode(session.toJson()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<_HttpResult> _request(
    String method,
    String url, {
    Map<String, String>? cookies,
    Map<String, Object?>? body,
  }) async {
    final client = _httpClientFactory()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final uri = Uri.parse(url);
      final req = await client.openUrl(method, uri);
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      req.headers.set('Origin', '${uri.scheme}://${uri.host}');
      if (cookies != null && cookies.isNotEmpty) {
        final cookieHeader = cookies.entries
            .map((e) => '${e.key}=${e.value}')
            .join('; ');
        req.headers.set(HttpHeaders.cookieHeader, cookieHeader);
      }
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(body));
      }
      final res = await req.close().timeout(const Duration(seconds: 25));
      final rawBody = await res.transform(utf8.decoder).join();

      final nextCookies = <String, String>{...?cookies};
      for (final cookie in res.cookies) {
        if (cookie.value.isNotEmpty) {
          nextCookies[cookie.name] = cookie.value;
        }
      }
      final headers = <String, String>{};
      res.headers.forEach((name, values) {
        if (values.isNotEmpty) headers[name.toLowerCase()] = values.first;
      });
      return _HttpResult(
        statusCode: res.statusCode,
        body: rawBody,
        cookies: nextCookies,
        headers: headers,
      );
    } on SocketException {
      throw AuthException('No internet connection.');
    } finally {
      client.close();
    }
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

  static String _extractError(String raw, String fallback) {
    final data = _tryDecodeMap(raw);
    if (data == null) return fallback;
    final msg = data['message'] ?? data['error'] ?? data['detail'];
    return msg is String && msg.trim().isNotEmpty ? msg.trim() : fallback;
  }

  static DateTime? _decodeJwtExp(String jwt) {
    final parts = jwt.split('.');
    if (parts.length != 3) return null;
    try {
      final normalized = base64Url.normalize(parts[1]);
      final payload =
          jsonDecode(utf8.decode(base64Url.decode(normalized)))
              as Map<String, dynamic>;
      final exp = payload['exp'];
      if (exp is int) {
        return DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);
      }
    } catch (_) {}
    return null;
  }
}

class _HttpResult {
  const _HttpResult({
    required this.statusCode,
    required this.body,
    required this.cookies,
    required this.headers,
  });

  final int statusCode;
  final String body;
  final Map<String, String> cookies;
  final Map<String, String> headers;
}
