import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:eduai/core/monitoring/sentry_setup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Keeps what would have been sent to Sentry.
class _CapturingTransport implements Transport {
  final envelopes = <SentryEnvelope>[];

  @override
  Future<SentryId?> send(SentryEnvelope envelope) async {
    envelopes.add(envelope);
    return envelope.header.eventId;
  }
}

/// Answers every request with [status] and remembers the headers it got.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.status);

  final int status;
  final headersByUrl = <String, Map<String, dynamic>>{};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    headersByUrl[options.uri.toString()] = Map.of(options.headers);
    return ResponseBody.fromString('{}', status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

/// The API client's exact Sentry wiring ([instrumentApiDio]) on a real Dio,
/// with the SDK's own interceptor, adapter and matcher deciding.
void main() {
  late _CapturingTransport transport;
  late Hub hub;

  setUp(() {
    transport = _CapturingTransport();
    final options = SentryOptions(dsn: 'https://public@example.invalid/1')
      ..transport = transport;
    options.tracePropagationTargets
      ..clear()
      ..addAll(sentryTraceTargets());
    hub = Hub(options);
  });

  Dio apiDio(_StubAdapter adapter) {
    final dio = Dio(BaseOptions(baseUrl: 'https://app-api.edu-ai.eu'))
      ..httpClientAdapter = adapter;
    instrumentApiDio(dio, hub: hub);
    return dio;
  }

  Future<void> getIgnoringErrors(Dio dio, String path) async {
    try {
      await dio.get<dynamic>(path);
    } on DioException {
      // The failure itself is the point.
    }
  }

  test('sentry_dio matches the path as handed to Dio', () {
    final relative = RequestOptions(
      baseUrl: 'https://app-api.edu-ai.eu',
      path: '/api/x',
    );
    expect(relative.path, '/api/x');
    expect(relative.uri.toString(), 'https://app-api.edu-ai.eu/api/x');
    expect(
      containsTargetOrMatchesRegExp(sentryFailedRequestTargets(), relative.path),
      isTrue,
    );

    final absolute = RequestOptions(path: 'https://app-api.edu-ai.eu/api/x');
    expect(
      containsTargetOrMatchesRegExp(sentryFailedRequestTargets(), absolute.path),
      isTrue,
    );

    final r2 = RequestOptions(path: 'https://pub-0123.r2.dev/a.json');
    expect(
      containsTargetOrMatchesRegExp(sentryFailedRequestTargets(), r2.path),
      isFalse,
    );
  });

  test('a 5xx from the API is reported, relative or absolute', () async {
    final dio = apiDio(_StubAdapter(503));
    await getIgnoringErrors(dio, '/api/x');
    await getIgnoringErrors(dio, 'https://app-api.edu-ai.eu/api/y');

    expect(transport.envelopes, hasLength(2));
  });

  test('a 4xx from the API is not', () async {
    await getIgnoringErrors(apiDio(_StubAdapter(404)), '/api/x');

    expect(transport.envelopes, isEmpty);
  });

  test('a 5xx from another host is not', () async {
    await getIgnoringErrors(
      apiDio(_StubAdapter(503)),
      'https://pub-0123.r2.dev/a.json',
    );

    expect(transport.envelopes, isEmpty);
  });

  test('trace headers go to the API only', () async {
    final adapter = _StubAdapter(200);
    final dio = apiDio(adapter);
    await dio.get<dynamic>('/api/x');
    await dio.get<dynamic>('https://pub-0123.r2.dev/a.json');

    expect(
      adapter.headersByUrl['https://app-api.edu-ai.eu/api/x'],
      contains('sentry-trace'),
    );
    expect(
      adapter.headersByUrl['https://pub-0123.r2.dev/a.json'],
      isNot(contains('sentry-trace')),
    );
    expect(
      adapter.headersByUrl['https://pub-0123.r2.dev/a.json'],
      isNot(contains('baggage')),
    );
  });
}
