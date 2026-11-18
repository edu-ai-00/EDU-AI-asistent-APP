import 'package:eduai/core/monitoring/sentry_user.dart';
import 'package:flutter_test/flutter_test.dart';

/// The agreed policy: staff are identified by id and e-mail, everyone else —
/// pupils, guests, minors, and accounts whose role the response did not
/// name — by id and segment only. A name never reaches Sentry.
void main() {
  group('sentryUserFor', () {
    test('a teacher from /api/user gets id and e-mail', () {
      final user = sentryUserFor({
        'id': 42,
        'name': 'Jana Nováková',
        'email': 'jana@skola.cz',
        'role': 'teacher',
        'is_guest': false,
        'is_minor': false,
      })!;

      expect(user.id, '42');
      expect(user.email, 'jana@skola.cz');
      expect(user.data, {'segment': 'staff', 'role': 'teacher'});
      expect(user.name, isNull);
      expect(user.username, isNull);
    });

    test('an admin gets id and e-mail', () {
      final user = sentryUserFor({
        'id': 1,
        'email': 'admin@nobig.deals',
        'role': 'admin',
      })!;

      expect(user.email, 'admin@nobig.deals');
      expect(user.data?['segment'], 'staff');
    });

    test('a pupil gets the id only, even with an e-mail on file', () {
      final user = sentryUserFor({
        'id': 7,
        'name': 'Petr Svoboda',
        'email': 'petr@example.com',
        'role': 'student',
      })!;

      expect(user.id, '7');
      expect(user.email, isNull);
      expect(user.name, isNull);
      expect(user.data, {'segment': 'pupil', 'role': 'student'});
    });

    test('a guest gets the id only', () {
      final user = sentryUserFor({
        'id': 9,
        'name': 'Chytry Tucnak',
        'is_guest': true,
        'device_id': 'abc',
      })!;

      expect(user.email, isNull);
      expect(user.name, isNull);
      expect(user.data, {'segment': 'guest'});
    });

    test('the guest flag wins over a staff role', () {
      final user = sentryUserFor({
        'id': 9,
        'email': 'x@example.com',
        'role': 'teacher',
        'is_guest': 1,
      })!;

      expect(user.email, isNull);
      expect(user.data?['segment'], 'guest');
    });

    test('a minor from /api/user gets the id only, whatever the role says', () {
      final user = sentryUserFor({
        'id': 11,
        'email': 'kid@example.com',
        'role': 'teacher',
        'is_minor': true,
      })!;

      expect(user.email, isNull);
      expect(user.data, {'segment': 'minor', 'role': 'teacher'});
    });

    test('a minor flagged beside the user (code login) gets the id only', () {
      final user = sentryUserFor(
        {'id': 12, 'name': 'Anička', 'email': null},
        isMinor: true,
      )!;

      expect(user.email, isNull);
      expect(user.name, isNull);
      expect(user.data, {'segment': 'minor'});
    });

    test('a response without a role (OAuth exchange) fails closed', () {
      final user = sentryUserFor({
        'id': 42,
        'name': 'Jana Nováková',
        'email': 'jana@skola.cz',
      })!;

      expect(user.email, isNull);
      expect(user.data, {'segment': 'unknown'});
    });

    test('no account or no id means no user', () {
      expect(sentryUserFor(null), isNull);
      expect(sentryUserFor({'email': 'a@b.cz', 'role': 'teacher'}), isNull);
      expect(sentryUserFor({'id': ''}), isNull);
    });
  });

  // Without SentryFlutter.init these run against the no-op hub: login and
  // logout paths must work the same in tests and when Sentry is unreachable.
  test('identify and forget never throw without an initialised Sentry', () {
    expect(() => identifySentryUser({'id': 1, 'role': 'teacher'}), returnsNormally);
    expect(() => identifySentryUser(null), returnsNormally);
    expect(forgetSentryUser, returnsNormally);
    expect(clearSentryBreadcrumbs, returnsNormally);
  });
}
