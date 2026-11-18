import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// (tag, error type) pairs already sent as a Sentry log in this app session.
@visibleForTesting
final Set<String> silentLogsSent = {};

/// Log an exception that we're intentionally swallowing.
///
/// Replaces `catch (_) {}` blocks so failures are visible: printed in debug
/// builds, and in every build recorded in Sentry as a breadcrumb (context for
/// a later crash) and a warning log (so a failure that never crashes anything
/// still shows up across devices). The log goes out once per tag and error
/// type per app session: a catch block inside a loop or a retry would
/// otherwise spend the log quota on one failure.
///
/// Sentry gets the [tag] and the error's type only — never its message or
/// stack. The message is where swallowed errors carry user data: a database
/// error quotes the statement's parameters (answers, names, e-mails), a
/// FormatException the text it failed to parse, a DioException the URL. The
/// tag already says which catch block it was.
void silentLog(String tag, Object error, [StackTrace? stack]) {
  final type = error.runtimeType.toString();
  Sentry.addBreadcrumb(Breadcrumb(
    category: 'silent_log',
    message: tag,
    level: SentryLevel.warning,
    data: {'error_type': type},
  ));
  if (silentLogsSent.add('$tag|$type')) {
    Sentry.logger.warn(
      'silentLog $tag',
      attributes: {
        'silent_log.tag': SentryAttribute.string(tag),
        'error.type': SentryAttribute.string(type),
      },
    );
  }

  if (kReleaseMode) return;
  debugPrint('SILENTLOG[$tag] $error');
  developer.log(
    error.toString(),
    name: 'silent.$tag',
    error: error,
    stackTrace: stack,
  );
}
