import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eduai/core/util/silent_log.dart';

/// Secure storage for the auth token, with one-shot migration from
/// SharedPreferences (where the token used to live in plain text).
///
/// Maintains a synchronous in-memory cache so request interceptors can read
/// the token without `await`. Call [load] once at app start before runApp.
class AuthTokenStorage {
  static const String _tokenKey = 'auth_token';
  static const String _userIdKey = 'user_id';
  static const String _migrationFlag = 'auth_token_migrated_to_secure';

  AuthTokenStorage({
    required SharedPreferences prefs,
    FlutterSecureStorage? secureStorage,
  })  : _prefs = prefs,
        _secure = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure;

  String? _cachedToken;

  /// Load the token into memory. Migrates a SharedPreferences-stored token
  /// into secure storage on first run.
  Future<void> load() async {
    if (!(_prefs.getBool(_migrationFlag) ?? false)) {
      final legacy = _prefs.getString(_tokenKey);
      if (legacy != null && legacy.isNotEmpty) {
        try {
          await _secure.write(key: _tokenKey, value: legacy);
        } catch (_) {
          // If secure write fails (e.g. unsupported platform), keep legacy.
        }
      }
      // Always remove the legacy plaintext copy.
      await _prefs.remove(_tokenKey);
      await _prefs.setBool(_migrationFlag, true);
    }

    try {
      _cachedToken = await _secure.read(key: _tokenKey);
    } catch (_) {
      _cachedToken = null;
    }
  }

  /// Synchronous read for use inside Dio interceptors.
  String? get token => _cachedToken;

  bool get isAuthenticated => (_cachedToken ?? '').isNotEmpty;

  Future<void> setToken(String token) async {
    _cachedToken = token;
    await _secure.write(key: _tokenKey, value: token);
  }

  Future<void> clearToken() async {
    _cachedToken = null;
    try {
      await _secure.delete(key: _tokenKey);
    } catch (e, st) { silentLog('auth_token_storage', e, st); }
    await _prefs.remove(_userIdKey);
  }
}
