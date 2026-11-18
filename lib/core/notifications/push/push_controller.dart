import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/datasources/remote/notifications_remote_datasource.dart';
import '../../util/silent_log.dart';
import 'push_messaging.dart';

/// The user's answer to the in-app "Chceš dostávat upozornění?" card.
enum PushPrimingChoice { accepted, declined }

/// Push notifications for the signed-in session (NOTIF-3, spec §8).
///
/// Owns the device token's life on the server — register after login and on
/// every token refresh, unregister on logout — and turns incoming pushes into
/// app actions through [onForeground] / [onOpened].
///
/// With [messaging] null (web, desktop, or a build without the Firebase
/// dart-defines) every method is a no-op and [isAvailable] is false: the feed
/// alone carries notifications.
///
/// The OS permission is never asked at first launch. Novinky shows a priming
/// card first ([shouldOfferPriming]); only "Povolit" there, or the button in
/// the notification settings, raises the OS prompt.
class PushController {
  /// Per-account choice on the priming card. Cleared on logout, so the next
  /// person on a shared device is asked themselves.
  static const String primingChoiceKey = 'push_priming_choice_v1';

  /// The token last registered with the server, for the logout unregister.
  static const String registeredTokenKey = 'push_registered_token_v1';

  final PushMessaging? _messaging;
  final String? _platform;
  final NotificationsRemoteDataSource _remote;
  final SharedPreferences _prefs;
  final bool Function() _isAuthenticated;
  final Future<String?> Function() _appVersion;
  final FutureOr<void> Function(PushMessage message) _onForeground;
  final FutureOr<void> Function(PushMessage message) _onOpened;

  PushController({
    required PushMessaging? messaging,
    required String? platform,
    required NotificationsRemoteDataSource remote,
    required SharedPreferences prefs,
    required bool Function() isAuthenticated,
    Future<String?> Function()? appVersion,
    FutureOr<void> Function(PushMessage message)? onForeground,
    FutureOr<void> Function(PushMessage message)? onOpened,
  })  : _messaging = platform == null ? null : messaging,
        _platform = platform,
        _remote = remote,
        _prefs = prefs,
        _isAuthenticated = isAuthenticated,
        _appVersion = appVersion ?? (() async => null),
        _onForeground = onForeground ?? ((_) {}),
        _onOpened = onOpened ?? ((_) {});

  final List<StreamSubscription<Object?>> _subscriptions = [];
  final StreamController<PushMessage> _foreground =
      StreamController<PushMessage>.broadcast();
  bool _initialMessageTaken = false;

  /// Whether this build can receive pushes at all.
  bool get isAvailable => _messaging != null;

  /// Foreground pushes, after [onForeground] ran — for the in-app banner.
  Stream<PushMessage> get foregroundMessages => _foreground.stream;

  PushPrimingChoice? get primingChoice =>
      switch (_prefs.getString(primingChoiceKey)) {
        'accepted' => PushPrimingChoice.accepted,
        'declined' => PushPrimingChoice.declined,
        _ => null,
      };

  /// Start push for the session that just reached the main screen (any login
  /// path ends there). Safe to call on every mount.
  ///
  /// Handles a push whose tap launched the app, and re-registers the token
  /// when the OS permission is already granted — re-registering is also what
  /// ties the device to the current access token server-side.
  Future<void> start() async {
    final messaging = _messaging;
    if (messaging == null) return;
    try {
      if (!await messaging.initialize()) return;
      _listen(messaging);

      if (!_initialMessageTaken) {
        _initialMessageTaken = true;
        final initial = await messaging.getInitialMessage();
        if (initial != null) await _handleOpened(initial);
      }

      if (await messaging.authorization() == PushAuthorization.authorized) {
        await registerToken();
      }
    } catch (e, st) {
      silentLog('push:start', e, st);
    }
  }

  /// The OS permission, or null where push is not offered at all.
  Future<PushAuthorization?> authorization() async {
    final messaging = _messaging;
    if (messaging == null) return null;
    try {
      if (!await messaging.initialize()) return null;
      return await messaging.authorization();
    } catch (e, st) {
      silentLog('push:authorization', e, st);
      return null;
    }
  }

  /// Whether Novinky should show the priming card: push works here, the user
  /// has not answered it yet, and the OS has not already settled the matter.
  Future<bool> shouldOfferPriming() async {
    final messaging = _messaging;
    if (messaging == null || primingChoice != null) return false;
    try {
      if (!await messaging.initialize()) return false;
      return switch (await messaging.authorization()) {
        PushAuthorization.authorized => false,
        PushAuthorization.deniedPermanently => false,
        // iOS asks once; a denial there is final.
        PushAuthorization.denied => _platform != 'ios',
        PushAuthorization.notDetermined => true,
      };
    } catch (e, st) {
      silentLog('push:priming', e, st);
      return false;
    }
  }

  /// "Povolit" on the priming card: remember it, then raise the OS prompt.
  /// Returns whether notifications ended up allowed.
  Future<bool> acceptPriming() async {
    await _prefs.setString(primingChoiceKey, PushPrimingChoice.accepted.name);
    return requestPermissionAndRegister();
  }

  /// "Teď ne": remember it; the card does not come back for this account.
  Future<void> declinePriming() =>
      _prefs.setString(primingChoiceKey, PushPrimingChoice.declined.name);

  /// Ask the OS for permission and, when granted, register the token.
  Future<bool> requestPermissionAndRegister() async {
    final messaging = _messaging;
    if (messaging == null) return false;
    try {
      if (!await messaging.initialize()) return false;
      _listen(messaging);
      final status = await messaging.requestPermission();
      if (status != PushAuthorization.authorized) return false;
      await registerToken();
      return true;
    } catch (e, st) {
      silentLog('push:request-permission', e, st);
      return false;
    }
  }

  /// Send the current token to the server. Skipped without a session.
  Future<void> registerToken([String? token]) async {
    final messaging = _messaging;
    final platform = _platform;
    if (messaging == null || platform == null || !_hasSession) return;
    try {
      final value = token ?? await messaging.getToken();
      if (value == null || value.isEmpty) return;
      final result = await _remote.registerPushDevice(
        token: value,
        platform: platform,
        appVersion: await _appVersion(),
      );
      if (result.isSuccess) {
        await _prefs.setString(registeredTokenKey, value);
      }
    } catch (e, st) {
      silentLog('push:register', e, st);
    }
  }

  /// Logout: forget the token on the server — while the session can still
  /// authenticate the call, i.e. before `/api/logout` — and on the device, so
  /// the next account here starts with a fresh one.
  ///
  /// After a 401 the session is already gone and the DELETE is skipped; the
  /// server drops the device with its access token instead.
  Future<void> unregister() async {
    final token = _prefs.getString(registeredTokenKey);
    if (token == null) return; // never registered on this device
    try {
      if (_hasSession) {
        await _remote.unregisterPushDevice(token);
      }
    } catch (e, st) {
      silentLog('push:unregister', e, st);
    }
    final messaging = _messaging;
    if (messaging != null) {
      try {
        if (await messaging.initialize()) await messaging.deleteToken();
      } catch (e, st) {
        silentLog('push:delete-token', e, st);
      }
    }
    await _prefs.remove(registeredTokenKey);
  }

  /// Drop everything push keeps for the account. Logout.
  static Future<void> clearLocalState(SharedPreferences prefs) async {
    await prefs.remove(primingChoiceKey);
    await prefs.remove(registeredTokenKey);
  }

  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    _foreground.close();
  }

  // ── Internals ───────────────────────────────────────────────────────────

  bool get _hasSession {
    try {
      return _isAuthenticated();
    } catch (e, st) {
      silentLog('push:session', e, st);
      return false;
    }
  }

  void _listen(PushMessaging messaging) {
    if (_subscriptions.isNotEmpty) return;
    _subscriptions
      ..add(messaging.onTokenRefresh.listen(registerToken))
      ..add(messaging.onForegroundMessage.listen(_handleForeground))
      ..add(messaging.onMessageOpenedApp.listen(_handleOpened));
  }

  Future<void> _handleForeground(PushMessage message) async {
    try {
      await _onForeground(message);
    } catch (e, st) {
      silentLog('push:foreground', e, st);
    }
    if (!_foreground.isClosed) _foreground.add(message);
  }

  Future<void> _handleOpened(PushMessage message) async {
    try {
      await _onOpened(message);
    } catch (e, st) {
      silentLog('push:opened', e, st);
    }
  }
}
