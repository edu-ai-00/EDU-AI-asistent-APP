import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:eduai/core/network/api_interceptors.dart';
import 'package:eduai/core/services/auth_token_storage.dart';
import 'package:eduai/core/services/session_meta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Auth token storage stub that reports a fixed non-empty token without
/// touching platform secure storage.
class _FixedTokens extends AuthTokenStorage {
  _FixedTokens(SharedPreferences prefs) : super(prefs: prefs);

  @override
  String? get token => 'fixed-test-token';
}

/// Dio adapter that never hits the network. Answers the token-refresh call
/// with a valid rotation payload and everything else with 200 `{}`.
class _StubAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path.endsWith('/api/auth/refresh')) {
      final future = DateTime.now()
          .add(const Duration(minutes: 30))
          .toUtc()
          .toIso8601String();
      return ResponseBody.fromString(
        '{"token":"rotated-token","shared_device":true,'
        '"expires_at":"$future","session_started_at":"$future"}',
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString(
      '{}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A fixed, clearly-in-the-past last-active timestamp.
  final oldMs = DateTime.utc(2020, 1, 1).millisecondsSinceEpoch;

  test(
    'automated authenticated request does not reset the shared-device idle clock',
    () async {
      SharedPreferences.setMockInitialValues({
        'session_shared_device': true,
        'session_last_active_at': oldMs,
      });
      final prefs = await SharedPreferences.getInstance();
      final session = SessionMeta(prefs);
      final tokens = _FixedTokens(prefs);

      final dio = Dio(BaseOptions(baseUrl: 'https://test.local'));
      dio.httpClientAdapter = _StubAdapter();
      dio.interceptors.add(
        TokenRotationInterceptor(dio: dio, tokens: tokens, session: session),
      );

      // A background/automated authenticated call (not a user interaction).
      await dio.get('/api/courses');

      // The idle clock must be untouched — only genuine user interaction
      // (pointer/keyboard, via InactivityWatcher) may advance it. Otherwise
      // periodic background sync keeps resetting it and the 15-minute idle
      // logout never fires.
      expect(session.lastActiveAt!.millisecondsSinceEpoch, oldMs);
    },
  );

  test(
    'applyFromAuthResponse with markActive:false (token rotation) keeps the idle clock',
    () async {
      final future = DateTime.now()
          .add(const Duration(minutes: 30))
          .toUtc()
          .toIso8601String();
      SharedPreferences.setMockInitialValues({
        'session_shared_device': true,
        'session_last_active_at': oldMs,
      });
      final prefs = await SharedPreferences.getInstance();
      final session = SessionMeta(prefs);

      // Automated token rotation applies fresh token metadata but is NOT user
      // activity, so it must not advance the idle clock.
      await session.applyFromAuthResponse(
        {'shared_device': true, 'expires_at': future},
        markActive: false,
      );

      expect(session.lastActiveAt!.millisecondsSinceEpoch, oldMs);
    },
  );

  test(
    'applyFromAuthResponse defaults to marking activity (login)',
    () async {
      SharedPreferences.setMockInitialValues({
        'session_shared_device': true,
        'session_last_active_at': oldMs,
      });
      final prefs = await SharedPreferences.getInstance();
      final session = SessionMeta(prefs);

      // A genuine login should register activity (default markActive: true).
      await session.applyFromAuthResponse({'shared_device': true});

      expect(
        session.lastActiveAt!.millisecondsSinceEpoch,
        greaterThan(oldMs),
      );
    },
  );
}
