import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../util/silent_log.dart';

/// Searchable tag beside the user: guest, minor, staff, pupil or unknown.
const String _segmentTag = 'user.segment';

/// What Sentry may say about the account an event came from.
///
/// * Staff (role admin or teacher) — the server id and the e-mail: adults at
///   work, whom support has to be able to find.
/// * Everyone else — pupils, guests and minors — the server id and a segment
///   only. Never the e-mail, never the name, whatever [account] carries.
///
/// The IP address comes on top of either, set by Sentry itself.
///
/// [account] is a user map from the API: `/api/user`, or the `user` object of
/// an auth response. Only `/api/user` names the role; an auth response does
/// not, so a session started from one is "unknown" until the next session
/// restore reads `/api/user`. Unknown gets the pupil treatment — the policy
/// fails closed. [isMinor] covers the code login, which reports the minor flag
/// beside the user rather than inside it.
@visibleForTesting
SentryUser? sentryUserFor(Map<String, dynamic>? account, {bool isMinor = false}) {
  final id = account?['id'];
  if (account == null || id == null || '$id'.isEmpty) return null;

  final role = account['role'] is String ? account['role'] as String : null;
  final guest = _isTrue(account['is_guest']);
  final minor = isMinor || _isTrue(account['is_minor']);
  final staff = !guest && !minor && (role == 'admin' || role == 'teacher');
  final segment = guest
      ? 'guest'
      : minor
          ? 'minor'
          : staff
              ? 'staff'
              : role == null
                  ? 'unknown'
                  : 'pupil';

  final email = account['email'];
  return SentryUser(
    id: '$id',
    email: staff && email is String && email.isNotEmpty ? email : null,
    data: {
      'segment': segment,
      if (role != null) 'role': role,
    },
  );
}

int _epoch = 0;

/// Bumped by every [forgetSentryUser]. Read it before awaiting the response
/// an identity comes from, and hand it to [identifySentryUser]: a logout that
/// lands while the request is in flight then wins, instead of the late
/// response putting the departed account back on the next one's reports.
int get sentryUserEpoch => _epoch;

/// Attach [account] (see [sentryUserFor]) to every event from now on — unless
/// [epoch] is given and the account has been forgotten since it was read.
///
/// Called wherever a login or a session restore learns who is signed in.
/// Never throws and never waits: the scope is updated synchronously, only the
/// copy to the native SDK finishes later.
void identifySentryUser(
  Map<String, dynamic>? account, {
  bool isMinor = false,
  int? epoch,
}) {
  if (epoch != null && epoch != _epoch) return;
  final user = sentryUserFor(account, isMinor: isMinor);
  final segment = user?.data?['segment'];
  // Started together, not awaited one by one: each call changes the Dart
  // scope at once and only then waits for the native copy.
  _configure((scope) => Future.wait([
        scope.setUser(user),
        if (segment is String)
          scope.setTag(_segmentTag, segment)
        else
          scope.removeTag(_segmentTag),
      ]));
}

/// Forget the signed-in account: the user, its segment and every breadcrumb
/// recorded so far. Nothing from one account may reach the next one's reports
/// on a shared device (client rule 5.9).
void forgetSentryUser() {
  _epoch++;
  _configure((scope) => Future.wait([
        scope.setUser(null),
        scope.removeTag(_segmentTag),
        scope.clearBreadcrumbs(),
      ]));
}

/// Drop the breadcrumbs alone, keeping whoever is signed in by now.
void clearSentryBreadcrumbs() {
  _configure((scope) => scope.clearBreadcrumbs());
}

void _configure(FutureOr<void> Function(Scope scope) change) {
  try {
    final pending = Sentry.configureScope(change);
    if (pending is Future<void>) {
      unawaited(pending.catchError(
        (Object e, StackTrace st) => silentLog('sentry_user', e, st),
      ));
    }
  } catch (e, st) {
    silentLog('sentry_user', e, st);
  }
}

bool _isTrue(Object? value) => value == true || value == 1 || value == '1';
