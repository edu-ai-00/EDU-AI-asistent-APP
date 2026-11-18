import 'dart:async';

import 'package:eduai/core/monitoring/sentry_setup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() {
  group('sentryEnvironment', () {
    test('an explicit SENTRY_ENVIRONMENT wins', () {
      expect(
        sentryEnvironment(
          override: 'beta',
          isDebug: true,
          apiBaseUrl: 'https://app-api.edu-ai.eu',
        ),
        'beta',
      );
    });

    test('a debug build is development', () {
      expect(
        sentryEnvironment(
          override: '',
          isDebug: true,
          apiBaseUrl: 'https://app-api.edu-ai.eu',
        ),
        'development',
      );
    });

    test('a release build is named after its API', () {
      String env(String api) =>
          sentryEnvironment(override: '', isDebug: false, apiBaseUrl: api);

      expect(env('https://app-api.edu-ai.eu'), 'production');
      expect(env('https://app-api-stage.edu-ai.eu'), 'staging');
      expect(env('https://api-dev-8b6a.up.railway.app'), 'dev');
      expect(env('http://localhost:8000'), 'development');
      expect(env('http://127.0.0.1:8000'), 'development');
    });
  });

  group('sentryTraceTargets', () {
    // The SDK's own matcher — substring or unanchored regex on the full URL.
    bool propagates(String url, {String api = 'https://app-api.edu-ai.eu'}) =>
        containsTargetOrMatchesRegExp(sentryTraceTargets(apiBaseUrl: api), url);

    test('our API, every environment, and localhost carry trace headers', () {
      expect(propagates('https://app-api.edu-ai.eu/api/user'), isTrue);
      expect(propagates('https://app-api-stage.edu-ai.eu/api/user'), isTrue);
      expect(propagates('https://api-dev-8b6a.up.railway.app/api/user'), isTrue);
      expect(propagates('https://APP-API.edu-ai.eu/api/user'), isTrue);
      expect(propagates('http://localhost:8000/api/user'), isTrue);
      expect(propagates('http://127.0.0.1/api/user'), isTrue);
    });

    test("this build's API_URL host is added", () {
      expect(
        propagates('http://10.0.2.2:8000/api/user', api: 'http://10.0.2.2:8000'),
        isTrue,
      );
    });

    test('nothing else does — R2, other hosts, look-alikes', () {
      expect(
        propagates('https://pub-0123456789abcdef.r2.dev/courses/1/cover.png'),
        isFalse,
      );
      expect(
        propagates('https://eduai.0123.r2.cloudflarestorage.com/a.json?X-Amz-Signature=x'),
        isFalse,
      );
      expect(propagates('https://fonts.gstatic.com/s/poppins.woff2'), isFalse);
      expect(propagates('https://app-api.edu-ai.eu.evil.example/api'), isFalse);
      expect(propagates('https://app-apixedu-ai.eu/api'), isFalse);
      expect(
        propagates('https://example.com/?next=https://app-api.edu-ai.eu/api'),
        isFalse,
      );
      expect(propagates('https://localhost.example.com/'), isFalse);
    });
  });

  group('sentryFailedRequestTargets', () {
    // sentry_dio tests these against the path handed to Dio.
    bool reported(String path) =>
        containsTargetOrMatchesRegExp(sentryFailedRequestTargets(), path);

    test('relative API paths and absolute API URLs are reported', () {
      expect(reported('/api/user'), isTrue);
      expect(reported('https://app-api.edu-ai.eu/api/sync'), isTrue);
    });

    test('absolute URLs to other hosts are not', () {
      expect(reported('https://pub-0123.r2.dev/a.json'), isFalse);
      expect(reported('https://example.com/api/user'), isFalse);
    });
  });

  // The web start-up race: the bootstrap runs once, whichever way it starts.
  group('runOnceWithin', () {
    const deadline = Duration(milliseconds: 50);
    const pastDeadline = Duration(milliseconds: 120);

    test('Sentry in time: run from start, no fallback', () async {
      var runs = 0;
      var fallbacks = 0;
      runOnceWithin(
        deadline: deadline,
        start: (runOnce) => runOnce(),
        run: () async => runs++,
        fallback: (runOnce) {
          fallbacks++;
          runOnce();
        },
      );

      await Future<void>.delayed(pastDeadline);
      expect(runs, 1);
      expect(fallbacks, 0);
    });

    test('Sentry stalled: fallback runs it, a late call is ignored', () async {
      var runs = 0;
      var fallbacks = 0;
      Future<void> Function()? lateRunOnce;
      final stalled = Completer<void>();
      runOnceWithin(
        deadline: deadline,
        start: (runOnce) {
          lateRunOnce = runOnce;
          return stalled.future;
        },
        run: () async => runs++,
        fallback: (runOnce) {
          fallbacks++;
          runOnce();
        },
      );

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(runs, 0, reason: 'still within the deadline');

      await Future<void>.delayed(pastDeadline);
      expect(runs, 1);
      expect(fallbacks, 1);

      // The CDN finally answers: Sentry calls the app runner after all.
      await lateRunOnce!();
      stalled.complete();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(runs, 1);
      expect(fallbacks, 1);
    });

    test('no deadline (mobile): an init failure still starts the app once',
        () async {
      var runs = 0;
      var fallbacks = 0;
      runOnceWithin(
        start: (_) async => throw StateError('native init failed'),
        run: () async => runs++,
        fallback: (runOnce) {
          fallbacks++;
          runOnce();
        },
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(runs, 1);
      expect(fallbacks, 1);
    });

    test("the app's own failure is not swallowed and not run twice",
        () async {
      var runs = 0;
      var fallbacks = 0;
      final uncaught = <Object>[];
      await runZonedGuarded(() async {
        runOnceWithin(
          start: (runOnce) => runOnce(),
          run: () async {
            runs++;
            throw StateError('bootstrap failed');
          },
          fallback: (_) => fallbacks++,
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }, (error, _) => uncaught.add(error));

      expect(runs, 1);
      expect(fallbacks, 0);
      expect(uncaught, [isA<StateError>()]);
    });

    test('Sentry failing early: fallback runs at once, not at the deadline',
        () async {
      var runs = 0;
      runOnceWithin(
        deadline: const Duration(seconds: 5),
        start: (_) => Future<void>.error(StateError('init failed')),
        run: () async => runs++,
        fallback: (runOnce) => runOnce(),
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(runs, 1);
    });
  });

  test('configureSentry keeps a DSN and restricts propagation', () {
    final options = SentryFlutterOptions();
    configureSentry(options);

    expect(options.dsn, startsWith('https://'));
    expect(options.dsn, contains('ingest.de.sentry.io'));
    expect(options.tracePropagationTargets, sentryTraceTargets());
    expect(options.tracePropagationTargets, isNot(contains('.*')));
    expect(options.sendDefaultPii, isTrue);
    expect(options.maxRequestBodySize, MaxRequestBodySize.never);
    expect(options.captureNativeFailedRequests, isFalse);
    expect(options.replay.sessionSampleRate, 0);
    expect(options.replay.onErrorSampleRate, 1.0);
    expect(options.privacy.maskAllText, isTrue);
    expect(options.privacy.maskAllImages, isTrue);
    expect(options.enableLogs, isTrue);
    expect(options.beforeSend, isNotNull);
    expect(options.beforeBreadcrumb, isNotNull);
    expect(options.beforeSendTransaction, isNotNull);
  });
}
