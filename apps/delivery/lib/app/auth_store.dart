import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// JWT vault backed by platform-specific secure storage (iOS Keychain /
/// Android Keystore — SDS §7 diagram). The token mirrors what the NestJS
/// API issued in the `auth_token` cookie; we store it as a string and put
/// it back in the cookie header on each request.
class AuthStore {
  static const _tokenKey = 'biobloom.auth_token';
  static const _csrfKey = 'biobloom.csrf_token';
  static const _riderIdKey = 'biobloom.rider_id';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<bool> hasToken() async {
    final t = await _storage.read(key: _tokenKey);
    return t != null && t.isNotEmpty;
  }

  Future<String?> token() => _storage.read(key: _tokenKey);
  Future<String?> csrf() => _storage.read(key: _csrfKey);
  Future<String?> riderId() => _storage.read(key: _riderIdKey);

  Future<void> persist({
    required String token,
    required String csrf,
    required String riderId,
  }) async {
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _csrfKey, value: csrf);
    await _storage.write(key: _riderIdKey, value: riderId);
  }

  Future<void> clear() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _csrfKey);
    await _storage.delete(key: _riderIdKey);
  }
}
