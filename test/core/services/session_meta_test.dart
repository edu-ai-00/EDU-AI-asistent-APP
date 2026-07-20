import 'package:eduai/core/services/session_meta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Covers SessionMeta.inactivityRemaining(), which drives the live countdown in
/// the shared-device banner. It must reflect lastActiveAt (so it resets on user
/// activity), clamp to zero once the idle limit passes, and stay null for
/// non-shared sessions where no countdown is shown.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SessionMeta> sessionWith(Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    return SessionMeta(await SharedPreferences.getInstance());
  }

  test('returns null for a non-shared session (no countdown to show)', () async {
    final session = await sessionWith({'session_shared_device': false});
    expect(session.inactivityRemaining(), isNull);
  });

  test('counts down from the full limit right after activity', () async {
    final session = await sessionWith({
      'session_shared_device': true,
      'session_last_active_at': DateTime.now().millisecondsSinceEpoch,
    });

    final remaining = session.inactivityRemaining()!;
    // Just under the full 15 minutes (a few ms elapse during the call).
    expect(remaining, lessThanOrEqualTo(SessionMeta.inactivityLimit));
    expect(remaining, greaterThan(SessionMeta.inactivityLimit - const Duration(seconds: 2)));
  });

  test('reflects elapsed idle time in the middle of the window', () async {
    final fiveMinAgo = DateTime.now().subtract(const Duration(minutes: 5));
    final session = await sessionWith({
      'session_shared_device': true,
      'session_last_active_at': fiveMinAgo.millisecondsSinceEpoch,
    });

    final remaining = session.inactivityRemaining()!;
    // ~10 minutes left; allow a small slack for execution time.
    expect(remaining, lessThanOrEqualTo(const Duration(minutes: 10)));
    expect(remaining, greaterThan(const Duration(minutes: 9, seconds: 55)));
  });

  test('clamps to zero once the idle limit has passed', () async {
    final longAgo = DateTime.now().subtract(const Duration(hours: 1));
    final session = await sessionWith({
      'session_shared_device': true,
      'session_last_active_at': longAgo.millisecondsSinceEpoch,
    });

    expect(session.inactivityRemaining(), Duration.zero);
  });
}
