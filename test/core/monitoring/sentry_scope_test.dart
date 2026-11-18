import 'package:eduai/core/monitoring/sentry_user.dart';
import 'package:eduai/core/util/silent_log.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

class _NoSendTransport implements Transport {
  @override
  Future<SentryId?> send(SentryEnvelope envelope) async =>
      envelope.header.eventId;
}

/// Against a real (offline) Sentry hub: what identify, forget and silentLog
/// leave on the scope, and which logs they would send.
void main() {
  final logs = <SentryLog>[];

  setUp(() async {
    logs.clear();
    silentLogsSent.clear();
    await Sentry.init((options) {
      options
        ..dsn = 'https://public@example.invalid/1'
        ..transport = _NoSendTransport()
        ..beforeSendLog = (log) {
          logs.add(log);
          return null;
        };
    });
  });

  tearDown(Sentry.close);

  Scope scope() {
    late Scope current;
    Sentry.configureScope((s) => current = s);
    return current;
  }

  group('sentryUserEpoch', () {
    test('an identity read before a logout is dropped after it', () {
      final epoch = sentryUserEpoch;
      // Logout lands while /api/user is in flight …
      forgetSentryUser();
      // … and the response arrives afterwards.
      identifySentryUser({'id': 7, 'role': 'teacher'}, epoch: epoch);

      expect(scope().user, isNull);
      expect(scope().tags, isNot(contains('user.segment')));
    });

    test('an identity read in the same session is applied', () {
      forgetSentryUser();
      final epoch = sentryUserEpoch;
      identifySentryUser(
        {'id': 7, 'role': 'teacher', 'email': 'j@skola.cz'},
        epoch: epoch,
      );

      expect(scope().user?.id, '7');
      expect(scope().user?.email, 'j@skola.cz');
      expect(scope().tags['user.segment'], 'staff');
    });

    test('forget clears the user, its segment and the breadcrumbs', () async {
      identifySentryUser({'id': 7, 'role': 'student'});
      await Sentry.addBreadcrumb(Breadcrumb(message: 'previous pupil'));
      expect(scope().breadcrumbs, isNotEmpty);

      forgetSentryUser();

      expect(scope().user, isNull);
      expect(scope().tags, isNot(contains('user.segment')));
      expect(scope().breadcrumbs, isEmpty);
    });
  });

  group('silentLog', () {
    test('a breadcrumb every time, a Sentry log once per tag and type',
        () async {
      for (var i = 0; i < 5; i++) {
        silentLog('sync:pull', const FormatException('pupil answer'));
      }
      silentLog('sync:pull', StateError('other type'));
      silentLog('avatar', const FormatException('x'));
      await pumpEventQueue();

      final crumbs = scope()
          .breadcrumbs
          .where((crumb) => crumb.category == 'silent_log')
          .toList();
      expect(crumbs, hasLength(7));
      expect(logs, hasLength(3));
      expect(
        logs.map((log) => log.body),
        ['silentLog sync:pull', 'silentLog sync:pull', 'silentLog avatar'],
      );
    });

    test('neither carries the error message', () async {
      silentLog('sync:pull', const FormatException('Petr Svoboda'));
      await pumpEventQueue();

      final crumb = scope().breadcrumbs.last;
      expect(crumb.message, 'sync:pull');
      expect(crumb.data, {'error_type': 'FormatException'});
      expect(logs.single.body, isNot(contains('Petr')));
    });
  });
}
