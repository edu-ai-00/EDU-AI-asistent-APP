import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:sentry_dio/sentry_dio.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../network/api_endpoints.dart';
import '../util/silent_log.dart';
import 'sentry_privacy.dart';

/// Crash and error reporting: Sentry project `eduai-app` of the `no-big-deals`
/// organisation (EU region), one project for iOS, Android and web.
///
/// The DSN only lets a client *send* events, so it is public by design and
/// ships as the default. `--dart-define=SENTRY_DSN=…` points a build at
/// another project; a missing or empty define falls back to this one, never
/// to "off" — a store build that forgot its defines must still report.
const String _defaultDsn =
    'https://b28c91d4f0f01bfc6fda4ec271834ae9@o4512392608415744.ingest.de.sentry.io/4512396579110992';

const String _dsnDefine = String.fromEnvironment('SENTRY_DSN');
const String _environmentDefine = String.fromEnvironment('SENTRY_ENVIRONMENT');

/// Set by the web Docker build on Railway to `eduai@<version>+<commit>`, the
/// same name its source-map upload uses. Empty everywhere else, which keeps
/// the SDK's own `<bundle id>@<version>+<build>` (dist = build number) on iOS
/// and Android — the name their dSYM / mapping uploads are matched against.
const String _releaseDefine = String.fromEnvironment('SENTRY_RELEASE');

/// The UUID the Android store build uploads the R8 mapping under (see
/// .github/workflows/app-store.yml); empty in every other build.
const String _proguardUuidDefine =
    String.fromEnvironment('SENTRY_PROGUARD_UUID');

/// Every API environment, whatever API_URL this build was given.
const List<String> _apiHosts = [
  'app-api.edu-ai.eu',
  'app-api-stage.edu-ai.eu',
  'api-dev-8b6a.up.railway.app',
];
const List<String> _localHosts = ['localhost', '127.0.0.1'];

/// How long the web app waits for Sentry before starting without it.
const Duration _webInitDeadline = Duration(seconds: 5);

/// Initialise Sentry, then run [appRunner] under it.
///
/// Called first thing in `main`, so a failure anywhere in the bootstrap —
/// SharedPreferences, secure storage, theme restore — is reported too.
///
/// On web the SDK first loads Sentry's JavaScript bundle from
/// browser.sentry-cdn.com, with no timeout, and only then calls [appRunner];
/// every event is sent through that bundle too (JavascriptTransport). A
/// network that silently drops the CDN — a school firewall — would keep the
/// pupils on a blank page. So web waits [_webInitDeadline] at most and then
/// starts the app on its own, reporting what it can: the hub is already up by
/// then, and whatever it captures goes out once (if ever) the bundle arrives.
/// Mobile waits as long as it takes — its native SDKs fetch nothing — but on
/// every platform an init that fails before reaching [appRunner] still starts
/// the app.
Future<void> runWithSentry(FutureOr<void> Function() appRunner) {
  runOnceWithin(
    deadline: kIsWeb ? _webInitDeadline : null,
    start: (runOnce) =>
        SentryFlutter.init(configureSentry, appRunner: runOnce),
    run: () async => appRunner(),
    fallback: (runOnce) => runZonedGuarded(
      runOnce,
      (error, stack) => Sentry.captureException(error, stackTrace: stack),
    ),
  );
  return Future.value();
}

/// Calls [run] exactly once: from inside [start] when it gets that far (within
/// [deadline], if one is given), otherwise through [fallback] — when the
/// deadline passes, or as soon as [start] ends without having called it. A
/// call from [start] after that is ignored.
///
/// A failure of [run] itself is not handled here: it surfaces as an uncaught
/// error, where the handlers Sentry installed report it — as it did before
/// this wrapper existed.
@visibleForTesting
void runOnceWithin({
  Duration? deadline,
  required Future<void> Function(Future<void> Function() runOnce) start,
  required Future<void> Function() run,
  required void Function(Future<void> Function() runOnce) fallback,
}) {
  var ran = false;
  Future<void> runOnce() async {
    if (ran) return;
    ran = true;
    await run();
  }

  void fallBackIfNotRun() {
    if (!ran) fallback(runOnce);
  }

  final timer = deadline == null ? null : Timer(deadline, fallBackIfNotRun);
  unawaited(Future.sync(() => start(runOnce)).then<void>(
    (_) {},
    onError: (Object e, StackTrace st) {
      if (ran) Error.throwWithStackTrace(e, st);
      silentLog('sentry_init', e, st);
    },
  ).whenComplete(() {
    timer?.cancel();
    fallBackIfNotRun();
  }));
}

@visibleForTesting
void configureSentry(SentryFlutterOptions options) {
  // The SDK reads the SENTRY_* defines itself before this runs and takes an
  // empty one at face value, so every value is set explicitly here.
  options.dsn = _dsnDefine.isNotEmpty ? _dsnDefine : _defaultDsn;
  options.environment = sentryEnvironment();
  options.release = _releaseDefine.isNotEmpty ? _releaseDefine : null;
  if (_proguardUuidDefine.isNotEmpty) {
    options.proguardUuid = _proguardUuidDefine;
  }

  final verbose = kDebugMode || options.environment == 'development';
  options.tracesSampleRate = verbose ? 1.0 : 0.2;
  // The default is every URL. On web that puts sentry-trace/baggage on
  // requests to R2 and other third parties, whose CORS rules do not allow
  // those headers, and the browser then blocks the request outright.
  options.tracePropagationTargets
    ..clear()
    ..addAll(sentryTraceTargets());

  // Session Replay (iOS/Android only): never a whole session, always the
  // moments before an error, with every text and image masked.
  options.replay.sessionSampleRate = 0;
  options.replay.onErrorSampleRate = 1.0;
  options.privacy.maskAllText = true;
  options.privacy.maskAllImages = true;

  options.enableLogs = true;

  // For the sender's IP address; everything else this unlocks is stripped
  // again in sentry_privacy.dart.
  options.sendDefaultPii = true;
  options.maxRequestBodySize = MaxRequestBodySize.never;
  // Failed requests are reported by the API client alone (5xx from our own
  // API, see [sentryFailedRequestTargets]); the native layer would report any
  // host's, with whatever its URL carries.
  options.captureNativeFailedRequests = false;

  options.beforeSend = scrubEvent;
  options.beforeSendTransaction = scrubTransaction;
  options.beforeBreadcrumb = scrubBreadcrumb;
}

/// `SENTRY_ENVIRONMENT` when given; otherwise read off the build — a debug
/// build is development, and a release build is named after the API it talks
/// to (store builds get it from their channel, see dart_defines.sh).
@visibleForTesting
String sentryEnvironment({
  String override = _environmentDefine,
  bool isDebug = kDebugMode,
  String apiBaseUrl = ApiEndpoints.baseUrl,
}) {
  if (override.isNotEmpty) return override;
  if (isDebug) return 'development';
  final host = _hostOf(apiBaseUrl);
  if (_localHosts.contains(host)) return 'development';
  if (host.contains('-stage')) return 'staging';
  if (host.contains('-dev')) return 'dev';
  return 'production';
}

/// Which requests may carry the `sentry-trace` and `baggage` headers: our own
/// API (every environment plus this build's API_URL) and localhost, nothing
/// else.
///
/// The SDK tests each entry against the full URL twice — as a plain substring
/// and as an unanchored, case-insensitive regular expression. A bare
/// `app-api.edu-ai.eu` would therefore also match
/// `https://app-api.edu-ai.eu.example.com` or `https://x.com/?u=app-api.edu-ai.eu`,
/// and its dots match any character; hence anchored patterns with escaped
/// hosts, which as substrings never occur in a real URL.
@visibleForTesting
List<String> sentryTraceTargets({String apiBaseUrl = ApiEndpoints.baseUrl}) {
  final hosts = <String>{
    if (_hostOf(apiBaseUrl).isNotEmpty) _hostOf(apiBaseUrl),
    ..._apiHosts,
    ..._localHosts,
  };
  return [
    for (final host in hosts) '^https?://${RegExp.escape(host)}(:\\d+)?([/?#]|\$)',
  ];
}

/// Sentry for the API client's Dio; added last, as sentry_dio requires.
///
/// Spans and breadcrumbs for every call, trace headers (to [sentryTraceTargets]
/// only, which options carry) and an error report for a 5xx from the API —
/// 4xx answers are part of normal flows (wrong code, expired session) and
/// stay out of Sentry. [hub] is for tests.
void instrumentApiDio(Dio dio, {Hub? hub}) {
  dio.addSentry(
    hub: hub,
    failedRequestStatusCodes: [SentryStatusCode.range(500, 599)],
    failedRequestTargets: sentryFailedRequestTargets(),
  );
}

/// Which failed requests the API client reports (5xx only).
///
/// sentry_dio matches these against `RequestOptions.path` — the path exactly
/// as handed to Dio, not the resolved URI. That is relative (`/api/…`) for
/// every call the API client makes against its base URL, which `^/` stands
/// for; an absolute URL has to be one of [sentryTraceTargets].
List<String> sentryFailedRequestTargets({
  String apiBaseUrl = ApiEndpoints.baseUrl,
}) {
  return ['^/', ...sentryTraceTargets(apiBaseUrl: apiBaseUrl)];
}

String _hostOf(String url) => Uri.tryParse(url)?.host.toLowerCase() ?? '';
