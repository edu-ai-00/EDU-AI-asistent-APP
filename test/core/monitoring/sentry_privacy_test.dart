import 'package:eduai/core/monitoring/sentry_privacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

class _NoSendTransport implements Transport {
  @override
  Future<SentryId?> send(SentryEnvelope envelope) async =>
      envelope.header.eventId;
}

void main() {
  group('redactUrl', () {
    test('drops query, fragment and user info', () {
      expect(
        redactUrl('https://app.edu-ai.eu/consent/confirm?id=abc&code=XY12#top'),
        'https://app.edu-ai.eu/consent/confirm',
      );
      expect(
        redactUrl('https://user:pw@app-api.edu-ai.eu:8443/api/user'),
        'https://app-api.edu-ai.eu:8443/api/user',
      );
    });

    test('replaces the guardian magic-link token, page and API', () {
      expect(
        redactUrl('https://app.edu-ai.eu/consent/manage/s3cr3t-token'),
        'https://app.edu-ai.eu/consent/manage/[Filtered]',
      );
      expect(
        redactUrl('https://app-api.edu-ai.eu/api/consent/manage/s3cr3t/revoke'),
        'https://app-api.edu-ai.eu/api/consent/manage/[Filtered]/revoke',
      );
      expect(
        redactUrl('https://app-api.edu-ai.eu/api/consent/manage/request-link'),
        'https://app-api.edu-ai.eu/api/consent/manage/request-link',
      );
    });

    test('replaces class join codes, keeps course PINs', () {
      expect(redactUrl('/join/AB12'), '/join/[Filtered]');
      expect(
        redactUrl('https://app-api.edu-ai.eu/api/courses/pin/676767'),
        'https://app-api.edu-ai.eu/api/courses/pin/676767',
      );
    });

    test('leaves span descriptions readable', () {
      expect(
        redactUrlsIn('GET https://app-api.edu-ai.eu/api/consent/manage/tok?x=1'),
        'GET https://app-api.edu-ai.eu/api/consent/manage/[Filtered]',
      );
    });
  });

  group('scrubBreadcrumb', () {
    test('tap breadcrumbs lose the tapped text', () {
      final crumb = Breadcrumb.userInteraction(
        subCategory: 'click',
        viewId: 'quiz_option_2',
        viewClass: 'ElevatedButton',
        data: {
          'label': 'Paříž',
          'path': [
            {'element': 'ElevatedButton', 'label': 'Paříž'},
            {'element': 'Column', 'name': 'quiz_options'},
          ],
        },
      );

      final data = scrubBreadcrumb(crumb, Hint())!.data!;
      expect(data.containsKey('label'), isFalse);
      expect(data['path'], [
        {'element': 'ElevatedButton'},
        {'element': 'Column', 'name': 'quiz_options'},
      ]);
      expect(data['view.id'], 'quiz_option_2');
    });

    test('HTTP breadcrumbs lose query and credential path segments', () {
      final crumb = Breadcrumb.http(
        url: Uri.parse('https://app-api.edu-ai.eu/api/consent/manage/tok'),
        method: 'GET',
        statusCode: 200,
        httpQuery: 'email=a@b.cz',
      );

      final data = scrubBreadcrumb(crumb, Hint())!.data!;
      expect(data['url'], 'https://app-api.edu-ai.eu/api/consent/manage/[Filtered]');
      expect(data.containsKey('http.query'), isFalse);
      expect(data['status_code'], 200);
    });

    test('navigation breadcrumbs lose route arguments', () {
      final crumb = Breadcrumb(
        category: 'navigation',
        type: 'navigation',
        data: {
          'state': 'didPush',
          'to': '/join/AB12',
          'to_arguments': {'student': 'Petr Svoboda'},
        },
      );

      final data = scrubBreadcrumb(crumb, Hint())!.data!;
      expect(data, {'state': 'didPush', 'to': '/join/[Filtered]'});
    });
  });

  test('scrubEvent redacts credential URLs in exception values and messages',
      () {
    final event = SentryEvent(
      exceptions: [
        SentryException(
          type: 'DioException',
          value: 'DioException [bad response]: GET '
              'https://app-api.edu-ai.eu/api/consent/manage/s3cr3t?x=1 '
              'returned 500 (see package:eduai/main.dart)',
        ),
      ],
      message: SentryMessage(
        'Join failed for /join/AB12, retrying',
        template: 'Join failed for %s',
        params: ['/join/AB12', 3],
      ),
    );

    final scrubbed = scrubEvent(event, Hint())!;
    expect(
      scrubbed.exceptions!.single.value,
      'DioException [bad response]: GET '
      'https://app-api.edu-ai.eu/api/consent/manage/[Filtered] '
      'returned 500 (see package:eduai/main.dart)',
    );
    expect(
      scrubbed.message!.formatted,
      'Join failed for /join/[Filtered], retrying',
    );
    expect(scrubbed.message!.template, 'Join failed for %s');
    expect(scrubbed.message!.params, ['/join/[Filtered]', 3]);
  });

  test('device name and server name never leave an event', () {
    final event = SentryEvent(serverName: 'Aniccas-iPhone');
    event.contexts.device =
        SentryDevice(name: 'Aniccas-iPhone', model: 'iPhone15,2');

    final scrubbed = scrubEvent(event, Hint())!;
    expect(scrubbed.contexts.device!.name, isNull);
    expect(scrubbed.contexts.device!.model, 'iPhone15,2');
    expect(scrubbed.serverName, isNull);
  });

  test('… nor a transaction', () async {
    SentryTransaction? sent;
    final options = SentryOptions(dsn: 'https://public@example.invalid/1')
      ..transport = _NoSendTransport()
      ..tracesSampleRate = 1.0
      ..beforeSendTransaction = (transaction, hint) {
        // What the SDK's enrichers put there with sendDefaultPii on.
        transaction.contexts.device = SentryDevice(name: 'Aniccas-iPhone');
        transaction.serverName = 'Aniccas-iPhone';
        return sent = scrubTransaction(transaction, hint);
      };
    final hub = Hub(options);

    await hub.startTransaction('ui.load', 'navigation').finish();
    await pumpEventQueue();

    expect(sent, isNotNull);
    expect(sent!.contexts.device!.name, isNull);
    expect(sent!.serverName, isNull);
  });

  test('scrubEvent strips the request to URL, method and harmless headers', () {
    final event = SentryEvent(
      request: SentryRequest(
        url: 'https://app.edu-ai.eu/consent/manage/tok',
        method: 'POST',
        queryString: 'code=XY12',
        cookies: 'session=1',
        data: {'answer': 'Paříž'},
        headers: {
          'Authorization': 'Bearer 1|abc',
          'Cookie': 'session=1',
          'X-Admin-Key': 'k',
          'Accept-Language': 'cs',
          'User-Agent': 'Mozilla/5.0',
        },
      ),
      breadcrumbs: [
        Breadcrumb(category: 'ui.click', data: {'label': 'Petr Svoboda'}),
      ],
    );
    event.contexts.response = SentryResponse(
      statusCode: 500,
      headers: {'set-cookie': 'x'},
      data: {'email': 'a@b.cz'},
    );

    final scrubbed = scrubEvent(event, Hint())!;
    final request = scrubbed.request!;
    expect(request.url, 'https://app.edu-ai.eu/consent/manage/[Filtered]');
    expect(request.method, 'POST');
    expect(request.queryString, isNull);
    expect(request.cookies, isNull);
    expect(request.data, isNull);
    expect(request.headers, {'Accept-Language': 'cs', 'User-Agent': 'Mozilla/5.0'});

    final response = scrubbed.contexts.response!;
    expect(response.statusCode, 500);
    expect(response.headers, isEmpty);
    expect(response.data, isNull);

    expect(scrubbed.breadcrumbs!.single.data, isEmpty);
  });
}
