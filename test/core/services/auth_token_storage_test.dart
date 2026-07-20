import 'package:eduai/core/services/auth_token_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Regression tests for BR-5M2K9Z: on iOS the Keychain-backed secure token
/// survives app deletion, while SharedPreferences and the local DB are wiped.
/// After a delete+reinstall the stale token must be dropped so the app starts
/// unauthenticated instead of silently resuming a previous guest session.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const tokenKey = 'auth_token';
  const migrationFlag = 'auth_token_migrated_to_secure';

  test(
    'reinstall (no migration flag, no legacy token) clears surviving secure token',
    () async {
      // Keychain survived the uninstall; SharedPreferences was wiped.
      FlutterSecureStorage.setMockInitialValues({tokenKey: 'stale-guest-token'});
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final storage = AuthTokenStorage(prefs: prefs);
      await storage.load();

      expect(storage.token, isNull);
      expect(storage.isAuthenticated, isFalse);
    },
  );

  test(
    'app update (migration flag already set) keeps the valid secure token',
    () async {
      FlutterSecureStorage.setMockInitialValues({tokenKey: 'valid-token'});
      SharedPreferences.setMockInitialValues({migrationFlag: true});
      final prefs = await SharedPreferences.getInstance();

      final storage = AuthTokenStorage(prefs: prefs);
      await storage.load();

      // Established users must NOT be logged out on a plain update.
      expect(storage.token, 'valid-token');
      expect(storage.isAuthenticated, isTrue);
    },
  );

  test(
    'legacy plaintext token migrates on first run and is not cleared',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({tokenKey: 'legacy-token'});
      final prefs = await SharedPreferences.getInstance();

      final storage = AuthTokenStorage(prefs: prefs);
      await storage.load();

      expect(storage.token, 'legacy-token');
      // Plaintext copy removed, migration flag set.
      expect(prefs.getString(tokenKey), isNull);
      expect(prefs.getBool(migrationFlag), isTrue);
    },
  );
}
