import 'dart:async';
import 'dart:ui' show DartPluginRegistrant;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../util/silent_log.dart';
import '../notification_event_queue.dart';
import 'push_config.dart';
import 'push_messaging.dart';

/// Runs for a push that arrives while the app is in the background or not
/// running (Android; iOS only for content-available messages, which the
/// server does not send).
///
/// It lives in its own isolate: no providers, no UI, no Firebase calls. All
/// it does is note `delivered` for the notification so the statistics see it
/// even if the user never taps it; the OS shows the notification itself.
/// Top-level and kept from tree shaking by the pragma, as the plugin requires.
@pragma('vm:entry-point')
Future<void> pushBackgroundMessageHandler(RemoteMessage message) async {
  try {
    DartPluginRegistrant.ensureInitialized();
    final id = message.data['notification_id'];
    if (id is! String || id.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await NotificationEventQueue.recordInBackground(
      prefs,
      id,
      NotificationEventType.delivered,
    );
  } catch (e, st) {
    silentLog('push:background', e, st);
  }
}

/// [PushMessaging] on Firebase Cloud Messaging (FCM fronts APNs on iOS).
///
/// Only ever constructed for Android/iOS builds that carry the Firebase
/// dart-defines — see `createPushMessaging`.
class FirebasePushMessaging implements PushMessaging {
  final FirebaseOptions _options;

  FirebasePushMessaging(this._options);

  /// From [config] for [platform] (`android` / `ios`).
  factory FirebasePushMessaging.fromConfig(PushConfig config, String platform) {
    return FirebasePushMessaging(FirebaseOptions(
      apiKey: config.apiKey,
      appId: config.appIdFor(platform),
      messagingSenderId: config.messagingSenderId,
      projectId: config.projectId,
      iosBundleId: config.iosBundleId.isEmpty ? null : config.iosBundleId,
    ));
  }

  static Future<bool>? _initializing;

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  @override
  Future<bool> initialize() => _initializing ??= _initialize();

  Future<bool> _initialize() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: _options);
      }
      FirebaseMessaging.onBackgroundMessage(pushBackgroundMessageHandler);
      return true;
    } catch (e, st) {
      silentLog('push:init', e, st);
      // Let a later start try again (e.g. a transient platform error).
      _initializing = null;
      return false;
    }
  }

  @override
  Future<PushAuthorization> authorization() async {
    final settings = await _messaging.getNotificationSettings();
    return _map(settings.authorizationStatus);
  }

  @override
  Future<PushAuthorization> requestPermission() async {
    final settings = await _messaging.requestPermission();
    return _map(settings.authorizationStatus);
  }

  @override
  Future<String?> getToken() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      // FCM cannot mint a token before APNs has handed one to the app, which
      // can take a moment after the permission is granted.
      String? apns;
      for (var attempt = 0; attempt < 5 && apns == null; attempt++) {
        apns = await _messaging.getAPNSToken();
        if (apns == null) await Future<void>.delayed(const Duration(seconds: 1));
      }
      if (apns == null) return null;
    }
    return _messaging.getToken();
  }

  @override
  Future<void> deleteToken() => _messaging.deleteToken();

  @override
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  @override
  Stream<PushMessage> get onForegroundMessage =>
      FirebaseMessaging.onMessage.map(_toPushMessage);

  @override
  Stream<PushMessage> get onMessageOpenedApp =>
      FirebaseMessaging.onMessageOpenedApp.map(_toPushMessage);

  @override
  Future<PushMessage?> getInitialMessage() async {
    final message = await _messaging.getInitialMessage();
    return message == null ? null : _toPushMessage(message);
  }

  static PushMessage _toPushMessage(RemoteMessage message) =>
      PushMessage.fromData(
        message.data,
        title: message.notification?.title,
        body: message.notification?.body,
      );

  static PushAuthorization _map(AuthorizationStatus status) =>
      switch (status) {
        AuthorizationStatus.authorized ||
        AuthorizationStatus.provisional =>
          PushAuthorization.authorized,
        AuthorizationStatus.notDetermined => PushAuthorization.notDetermined,
        AuthorizationStatus.deniedPermanently =>
          PushAuthorization.deniedPermanently,
        AuthorizationStatus.denied => PushAuthorization.denied,
      };
}

/// The messaging SDK for this build, or null when push is not offered here:
/// web and desktop (no push by design), or a build without the Firebase
/// dart-defines. Null makes the whole push layer a no-op.
PushMessaging? createPushMessaging({
  PushConfig config = PushConfig.fromEnvironment,
  String? platform,
}) {
  final name = platform ?? pushPlatformName();
  if (name == null || !config.isCompleteFor(name)) return null;
  return FirebasePushMessaging.fromConfig(config, name);
}
