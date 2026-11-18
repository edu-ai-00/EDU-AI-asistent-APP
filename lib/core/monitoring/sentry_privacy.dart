import 'package:sentry_flutter/sentry_flutter.dart';

// What may leave the device with an error, breadcrumb or span.
//
// `sendDefaultPii` is on so Sentry records the sender's IP address, which is
// all it is wanted for here. It also lets the SDK attach things that must not
// reach Sentry from an app used by children (client rule 5.9):
//  * the text of whatever was tapped — on a quiz that is the answer, in a
//    class roster a pupil's name;
//  * the headers of a failed API request (Authorization: Bearer …);
//  * full URLs, which on the guardian consent pages carry a magic-link token
//    in the path (/consent/manage/<token>, and the API call behind it) or a
//    confirmation code in the query (/consent/confirm?id=…&code=…);
//  * the device's host name, often its owner's first name.
// The hooks below strip those again. Bodies are never captured at all
// (maxRequestBodySize: never, see sentry_setup.dart); these drop them anyway.

const String _filtered = '[Filtered]';

/// Request headers kept on an event: none of them identifies or authenticates
/// anyone. Everything else — Authorization, Cookie, X-Admin-Key and whatever
/// is added later — is dropped.
const Set<String> _keptHeaders = {
  'accept',
  'accept-language',
  'content-type',
  'user-agent',
};

/// [url] without its query, fragment and user info, and with the path
/// segments that are credentials rather than routes replaced:
/// `/consent/manage/<token>` (page and API alike) and `/join/<class code>`.
/// Course PINs stay: they open a public course and say which one failed.
String redactUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return _filtered;

  final segments = uri.pathSegments.toList();
  for (var i = 0; i < segments.length - 1; i++) {
    final isManageToken = segments[i] == 'manage' &&
        i > 0 &&
        segments[i - 1] == 'consent' &&
        segments[i + 1] != 'request-link';
    if (isManageToken || segments[i] == 'join') {
      segments[i + 1] = _filtered;
    }
  }

  final origin = uri.hasAuthority
      ? '${uri.hasScheme ? '${uri.scheme}:' : ''}//${uri.host}'
          '${uri.hasPort ? ':${uri.port}' : ''}'
      : '';
  final root = uri.path.startsWith('/') ? '/' : '';
  return '$origin$root${segments.join('/')}';
}

/// An absolute URL, or a path that starts a word (`package:eduai/main.dart`
/// is neither), as group 2; group 1 is the character before it. No
/// lookbehind: Safari before 16.4 — older school iPads — rejects it.
final RegExp _urlInText = RegExp(
  r'''(^|[^\w.~-])((?:https?://|/)[^\s"'<>()\[\]{},;]*)''',
);

/// [redactUrl] applied to every URL or path inside free text — a span
/// description (`GET https://app-api.edu-ai.eu/api/consent/manage/…`), an
/// exception message quoting the request — leaving the rest of the text as
/// it is.
String redactUrlsIn(String text) {
  return text.replaceAllMapped(
    _urlInText,
    (m) => '${m[1]}${redactUrl(m[2]!)}',
  );
}

/// `beforeSend`: the request (the page URL on web, the failed call for an API
/// error), the response, the exception and message texts (a DioException
/// quotes its URL) and every breadcrumb that rides along — on iOS those
/// include the native layer's own.
SentryEvent? scrubEvent(SentryEvent event, Hint hint) {
  _scrubCommon(event);
  for (final exception in event.exceptions ?? const <SentryException>[]) {
    final value = exception.value;
    if (value != null) exception.value = redactUrlsIn(value);
  }
  final message = event.message;
  if (message != null) {
    message.formatted = redactUrlsIn(message.formatted);
    final template = message.template;
    if (template != null) message.template = redactUrlsIn(template);
    message.params = message.params
        ?.map((param) => param is String ? redactUrlsIn(param) : param)
        .toList();
  }
  event.breadcrumbs = event.breadcrumbs
      ?.map((crumb) => scrubBreadcrumb(crumb, hint))
      .whereType<Breadcrumb>()
      .toList();
  return event;
}

/// `beforeSendTransaction`: span descriptions and URL data carry the same
/// paths as the breadcrumbs.
SentryTransaction? scrubTransaction(SentryTransaction transaction, Hint hint) {
  _scrubCommon(transaction);
  for (final span in transaction.spans) {
    final description = span.context.description;
    if (description != null) {
      span.context.description = redactUrlsIn(description);
    }
    // Edited in place: the spans are finished by now, and a finished span
    // ignores setData/removeData.
    final data = span.data;
    final url = data['url'];
    if (url is String) data['url'] = redactUrl(url);
    data
      ..remove('http.query')
      ..remove('http.fragment');
  }
  return transaction;
}

/// `beforeBreadcrumb`: tap labels, request URLs and route arguments.
Breadcrumb? scrubBreadcrumb(Breadcrumb? crumb, Hint hint) {
  final data = crumb?.data;
  if (crumb == null || data == null) return crumb;

  final scrubbed = Map<String, dynamic>.of(data);
  final category = crumb.category ?? '';
  if (crumb.type == 'http' || category == 'http') {
    final url = scrubbed['url'];
    if (url is String) scrubbed['url'] = redactUrl(url);
    scrubbed
      ..remove('http.query')
      ..remove('http.fragment');
  } else if (category.startsWith('ui.')) {
    // The tapped widget's text, and the text of each widget on the way to it.
    scrubbed.remove('label');
    final path = scrubbed['path'];
    if (path is List) {
      scrubbed['path'] = [
        for (final step in path)
          step is Map ? (Map<String, dynamic>.of(step.cast())..remove('label')) : step,
      ];
    }
  } else if (category == 'navigation') {
    scrubbed
      ..remove('from_arguments')
      ..remove('to_arguments');
    for (final key in const ['from', 'to']) {
      final name = scrubbed[key];
      if (name is String) scrubbed[key] = redactUrl(name);
    }
  }
  crumb.data = scrubbed;
  return crumb;
}

void _scrubCommon(SentryEvent event) {
  // The device's name: with sendDefaultPii the Dart SDK reports the host name
  // here, which on a phone is often the child's ("Aničky iPhone"); the native
  // layers' device context may carry one too. The server name is the same
  // host name on the Dart side.
  event.contexts.device?.name = null;
  event.serverName = null;

  final request = event.request;
  if (request != null) {
    final url = request.url;
    // Rebuilt rather than edited: body, cookies, query and fragment are left
    // behind, and only the harmless headers are carried over.
    event.request = SentryRequest(
      url: url == null ? null : redactUrl(url),
      method: request.method,
      headers: {
        for (final header in request.headers.entries)
          if (_keptHeaders.contains(header.key.toLowerCase()))
            header.key: header.value,
      },
    );
  }

  final response = event.contexts.response;
  if (response != null) {
    event.contexts.response = SentryResponse(
      statusCode: response.statusCode,
      bodySize: response.bodySize,
    );
  }

  final transaction = event.transaction;
  if (transaction != null && transaction.startsWith('/')) {
    event.transaction = redactUrl(transaction);
  }
}
