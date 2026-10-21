import 'package:dio/dio.dart';

import 'auth_store.dart';

/// HTTP wrapper around the NestJS API. Reads the JWT + CSRF token from the
/// AuthStore and attaches them on every request. The base URL defaults to
/// http://10.0.2.2:4000 (Android emulator's host alias) but should be set
/// to the public ALB hostname in release builds via --dart-define.
///
/// Phase 11 adds certificate pinning to this client (SDS §7 diagram).
class ApiClient {
  static const String _defaultBase = 'http://10.0.2.2:4000';

  final AuthStore _auth;
  final Dio _dio;

  ApiClient(this._auth)
      : _dio = Dio(
          BaseOptions(
            baseUrl: const String.fromEnvironment('API_BASE_URL', defaultValue: _defaultBase),
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 15),
            headers: {'Accept': 'application/json'},
          ),
        );

  /// CSRF priming + login. Returns the rider's id from the /api/auth/me
  /// follow-up call so AuthStore can stash it next to the token.
  Future<({String riderId, String email})> login({
    required String email,
    required String password,
  }) async {
    // Prime CSRF cookie + token.
    final csrfRes = await _dio.get<Map<String, dynamic>>('/api/auth/csrf');
    final csrf = (csrfRes.data?['csrfToken'] as String?) ?? '';
    final cookieFromCsrf = _extractCookie(csrfRes, 'csrf-token') ?? '';

    final loginRes = await _dio.post<Map<String, dynamic>>(
      '/api/auth/login',
      data: {'email': email, 'password': password},
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': csrf,
          'Cookie': 'csrf-token=$cookieFromCsrf',
        },
      ),
    );
    final authCookie = _extractCookie(loginRes, 'auth_token');
    if (authCookie == null) {
      throw Exception('auth_token cookie not returned');
    }
    final role = (loginRes.data?['role'] as String?) ?? '';
    if (role != 'DELIVERY') {
      throw Exception('This app is for delivery riders only (got role $role)');
    }
    final riderId = (loginRes.data?['userId'] as String?) ?? '';
    final returnedEmail = (loginRes.data?['email'] as String?) ?? email;

    await _auth.persist(token: authCookie, csrf: csrf, riderId: riderId);
    return (riderId: riderId, email: returnedEmail);
  }

  Future<void> logout() async {
    try {
      final csrf = await _auth.csrf();
      final token = await _auth.token();
      if (token != null) {
        await _dio.post<dynamic>(
          '/api/auth/logout',
          options: Options(
            headers: {
              'X-CSRF-Token': csrf,
              'Cookie': _cookieHeader(token: token, csrf: csrf),
            },
          ),
        );
      }
    } catch (_) {
      // best-effort; we always clear local state below.
    }
    await _auth.clear();
  }

  Future<List<Map<String, dynamic>>> listAssignments() async {
    final res = await _dio.get<List<dynamic>>(
      '/api/delivery/assignments',
      options: await _authedOptions(),
    );
    return (res.data ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> registerFcmToken(String token) async {
    await _dio.post<dynamic>(
      '/api/delivery/fcm-token',
      data: {'fcmToken': token},
      options: await _authedOptions(),
    );
  }

  Future<void> updateStatus({
    required String assignmentId,
    required String status,
    double? lat,
    double? lng,
    String? notes,
  }) async {
    await _dio.post<dynamic>(
      '/api/delivery/assignments/$assignmentId/status',
      data: {
        'status': status,
        if (lat != null) 'gpsLat': lat,
        if (lng != null) 'gpsLng': lng,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      },
      options: await _authedOptions(),
    );
  }

  Future<void> uploadProof({
    required String assignmentId,
    required String photoUrl,
  }) async {
    await _dio.post<dynamic>(
      '/api/delivery/assignments/$assignmentId/proof',
      data: {'photoUrl': photoUrl},
      options: await _authedOptions(),
    );
  }

  Future<Options> _authedOptions() async {
    final token = await _auth.token();
    final csrf = await _auth.csrf();
    return Options(
      headers: {
        'Content-Type': 'application/json',
        if (csrf != null) 'X-CSRF-Token': csrf,
        if (token != null) 'Cookie': _cookieHeader(token: token, csrf: csrf),
      },
    );
  }

  String _cookieHeader({required String? token, String? csrf}) {
    final parts = <String>[];
    if (token != null && token.isNotEmpty) parts.add('auth_token=$token');
    if (csrf != null && csrf.isNotEmpty) parts.add('csrf-token=$csrf');
    return parts.join('; ');
  }

  String? _extractCookie(Response<dynamic> res, String name) {
    final raw = res.headers['set-cookie'];
    if (raw == null) return null;
    for (final entry in raw) {
      if (entry.startsWith('$name=')) {
        return entry.split(';').first.split('=').sublist(1).join('=');
      }
    }
    return null;
  }
}
