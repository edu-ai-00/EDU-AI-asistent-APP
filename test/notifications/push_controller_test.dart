// NOTIF-3 — push on Android/iOS only, and only in builds that carry the
// Firebase dart-defines; everywhere else the push layer is a no-op and the
// feed carries the notifications (spec §0, §8). Where push works: the token is
// registered after login and on refresh, unregistered on logout, the priming
// card decides when the OS is asked, and a tapped push becomes app_opened +
// clicked plus a deep link parked for MainScreen.
//
//   flutter test test/notifications/push_controller_test.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eduai/core/notifications/notification_event_queue.dart';
import 'package:eduai/core/notifications/push/firebase_push_messaging.dart';
import 'package:eduai/core/notifications/push/push_config.dart';
import 'package:eduai/core/notifications/push/push_controller.dart';
import 'package:eduai/core/notifications/push/push_messaging.dart';
import 'package:eduai/core/providers/core_providers.dart';
import 'package:eduai/core/providers/notification_providers.dart';
import 'package:eduai/core/services/auth_token_storage.dart';
import 'package:eduai/routing/deep_link.dart';

import 'fake_notifications_remote.dart';

class _FakeMessaging implements PushMessaging {
  PushAuthorization status;
  String? token = 'token-1';
  int deleteTokenCalls = 0;
  int initialMessageCalls = 0;
  PushMessage? initial;

  final tokenRefresh = StreamController<String>.broadcast();
  final foreground = StreamController<PushMessage>.broadcast();
  final opened = StreamController<PushMessage>.broadcast();

  _FakeMessaging({this.status = PushAuthorization.authorized});

  /// Not awaited: a close() future can wait on a listener that never comes.
  void dispose() {
    tokenRefresh.close();
    foreground.close();
    opened.close();
  }

  @override
  Future<bool> initialize() async => true;
  @override
  Future<PushAuthorization> authorization() async => status;
  @override
  Future<PushAuthorization> requestPermission() async => status;
  @override
  Future<String?> getToken() async => token;
  @override
  Future<void> deleteToken() async => deleteTokenCalls++;
  @override
  Stream<String> get onTokenRefresh => tokenRefresh.stream;
  @override
  Stream<PushMessage> get onForegroundMessage => foreground.stream;
  @override
  Stream<PushMessage> get onMessageOpenedApp => opened.stream;
  @override
  Future<PushMessage?> getInitialMessage() async {
    initialMessageCalls++;
    final message = initial;
    initial = null;
    return message;
  }
}

class _SignedIn extends AuthTokenStorage {
  _SignedIn({required super.prefs});

  @override
  String? get token => 'session-token';
  @override
  bool get isAuthenticated => true;
  @override
  Future<void> load() async {}
  @override
  Future<void> setToken(String token) async {}
  @override
  Future<void> clearToken() async {}
}

const _complete = PushConfig(
  apiKey: 'key',
  projectId: 'eduai',
  messagingSenderId: '123',
  androidAppId: '1:123:android:abc',
  iosAppId: '1:123:ios:abc',
  iosBundleId: 'com.eduai.eduaiapp',
);

void main() {
  late SharedPreferences prefs;
  late FakeNotificationsRemote remote;
  var authenticated = true;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    remote = FakeNotificationsRemote();
    authenticated = true;
  });

  PushController controller(
    PushMessaging? messaging, {
    String? platform = 'android',
    List<PushMessage>? opened,
    List<PushMessage>? foreground,
  }) {
    final c = PushController(
      messaging: messaging,
      platform: platform,
      remote: remote,
      prefs: prefs,
      isAuthenticated: () => authenticated,
      appVersion: () async => '1.0.26',
      onOpened: (m) => opened?.add(m),
      onForeground: (m) => foreground?.add(m),
    );
    addTearDown(c.dispose);
    return c;
  }

  group('no-op without push', () {
    test('this test build has no Firebase dart-defines', () {
      expect(PushConfig.fromEnvironment.isCompleteFor('android'), isFalse);
      expect(PushConfig.fromEnvironment.isCompleteFor('ios'), isFalse);
      expect(createPushMessaging(), isNull);
      expect(createPushMessaging(platform: 'ios'), isNull);
    });

    test('push is offered on Android and iOS only', () {
      expect(pushPlatformName(platform: TargetPlatform.android, isWeb: false),
          'android');
      expect(pushPlatformName(platform: TargetPlatform.iOS, isWeb: false), 'ios');
      expect(pushPlatformName(platform: TargetPlatform.android, isWeb: true),
          isNull);
      expect(pushPlatformName(platform: TargetPlatform.macOS, isWeb: false),
          isNull);
      expect(pushPlatformName(platform: TargetPlatform.windows, isWeb: false),
          isNull);
      expect(pushPlatformName(platform: TargetPlatform.linux, isWeb: false),
          isNull);
    });

    test('a complete config is needed, per platform', () {
      expect(_complete.isCompleteFor('android'), isTrue);
      expect(_complete.isCompleteFor('ios'), isTrue);
      expect(_complete.isCompleteFor(null), isFalse);
      expect(
        const PushConfig(apiKey: 'k', projectId: 'p', messagingSenderId: 's',
                androidAppId: 'a')
            .isCompleteFor('ios'),
        isFalse,
        reason: 'no iOS app id',
      );
      expect(createPushMessaging(config: _complete, platform: 'android'),
          isA<FirebasePushMessaging>());
    });

    test('every call is a harmless no-op', () async {
      final c = controller(null);

      expect(c.isAvailable, isFalse);
      await c.start();
      expect(await c.shouldOfferPriming(), isFalse);
      expect(await c.requestPermissionAndRegister(), isFalse);
      expect(await c.authorization(), isNull);
      await c.registerToken();
      await c.unregister();

      expect(remote.registeredDevices, isEmpty);
      expect(remote.unregisteredTokens, isEmpty);
    });

    test('messaging on a platform without push is ignored', () async {
      final c = controller(_FakeMessaging(), platform: null);

      expect(c.isAvailable, isFalse);
      await c.start();
      expect(remote.registeredDevices, isEmpty);
    });
  });

  group('token registration', () {
    test('start registers the token when notifications are allowed', () async {
      final c = controller(_FakeMessaging());

      await c.start();

      final device = remote.registeredDevices.single;
      expect(device.token, 'token-1');
      expect(device.platform, 'android');
      expect(device.appVersion, '1.0.26');
      expect(prefs.getString(PushController.registeredTokenKey), 'token-1');
    });

    test('start does not ask the OS and registers nothing when not allowed',
        () async {
      final messaging = _FakeMessaging(status: PushAuthorization.denied);
      final c = controller(messaging);

      await c.start();

      expect(remote.registeredDevices, isEmpty);
    });

    test('no session, no registration', () async {
      authenticated = false;
      final c = controller(_FakeMessaging());

      await c.start();

      expect(remote.registeredDevices, isEmpty);
    });

    test('a refreshed token is registered again', () async {
      final messaging = _FakeMessaging();
      final c = controller(messaging);
      await c.start();

      messaging.tokenRefresh.add('token-2');
      await pumpEventQueue();

      expect(remote.registeredDevices.map((d) => d.token), ['token-1', 'token-2']);
      expect(prefs.getString(PushController.registeredTokenKey), 'token-2');
    });

    test('logout: DELETE on the server, token dropped on the device',
        () async {
      final messaging = _FakeMessaging();
      final c = controller(messaging);
      await c.start();

      await c.unregister();

      expect(remote.unregisteredTokens, ['token-1']);
      expect(messaging.deleteTokenCalls, 1);
      expect(prefs.getString(PushController.registeredTokenKey), isNull);
    });

    test('after a 401 the DELETE is skipped, the local token still goes',
        () async {
      final messaging = _FakeMessaging();
      final c = controller(messaging);
      await c.start();
      authenticated = false;

      await c.unregister();

      expect(remote.unregisteredTokens, isEmpty);
      expect(messaging.deleteTokenCalls, 1);
      expect(prefs.getString(PushController.registeredTokenKey), isNull);
    });
  });

  group('priming', () {
    Future<bool> offer(PushAuthorization status, {String platform = 'android'}) =>
        controller(_FakeMessaging(status: status), platform: platform)
            .shouldOfferPriming();

    test('shown while the OS has not been asked or may still ask', () async {
      expect(await offer(PushAuthorization.notDetermined, platform: 'ios'), isTrue);
      // Android 13+ reports "not asked yet" as denied.
      expect(await offer(PushAuthorization.denied), isTrue);
    });

    test('not shown when the OS already settled it', () async {
      expect(await offer(PushAuthorization.authorized), isFalse);
      expect(await offer(PushAuthorization.deniedPermanently), isFalse);
      expect(await offer(PushAuthorization.denied, platform: 'ios'), isFalse);
    });

    test('not shown again once answered', () async {
      final c = controller(_FakeMessaging(status: PushAuthorization.denied));
      await c.declinePriming();

      expect(c.primingChoice, PushPrimingChoice.declined);
      expect(await c.shouldOfferPriming(), isFalse);
    });

    test('accepting asks the OS and registers on a yes', () async {
      final c = controller(
        _FakeMessaging(status: PushAuthorization.authorized),
      );

      expect(await c.acceptPriming(), isTrue);
      expect(c.primingChoice, PushPrimingChoice.accepted);
      expect(remote.registeredDevices.single.token, 'token-1');
    });

    test('accepting with an OS no: remembered, nothing registered', () async {
      final c = controller(_FakeMessaging(status: PushAuthorization.denied));

      expect(await c.acceptPriming(), isFalse);
      expect(c.primingChoice, PushPrimingChoice.accepted);
      expect(remote.registeredDevices, isEmpty);
    });
  });

  group('incoming pushes', () {
    test('the push that launched the app is handled once', () async {
      final messaging = _FakeMessaging()
        ..initial = const PushMessage(notificationId: '01JA', deepLink: '/quiz');
      final opened = <PushMessage>[];
      final c = controller(messaging, opened: opened);

      await c.start();
      await c.start(); // MainScreen mounts again after a re-login

      expect(opened.map((m) => m.deepLink), ['/quiz']);
      expect(messaging.initialMessageCalls, 1);
    });

    test('a tap from the background and a foreground push reach their hooks',
        () async {
      final messaging = _FakeMessaging();
      final opened = <PushMessage>[];
      final foreground = <PushMessage>[];
      final c = controller(messaging, opened: opened, foreground: foreground);
      final banners = <PushMessage>[];
      c.foregroundMessages.listen(banners.add);
      await c.start();

      messaging.opened.add(const PushMessage(notificationId: '01JB'));
      messaging.foreground.add(const PushMessage(notificationId: '01JC'));
      await pumpEventQueue();

      expect(opened.single.notificationId, '01JB');
      expect(foreground.single.notificationId, '01JC');
      expect(banners.single.notificationId, '01JC');
    });

    test('PushMessage reads the server data block', () {
      final message = PushMessage.fromData(
        {
          'notification_id': '01JX',
          'deep_link': '/course/ABC',
          'type_key': 'course_halfway',
        },
        title: 'Polovina kurzu za tebou',
        body: 'Jen tak dál!',
      );

      expect(message.notificationId, '01JX');
      expect(message.deepLink, '/course/ABC');
      expect(message.typeKey, 'course_halfway');
      expect(message.title, 'Polovina kurzu za tebou');
      expect(PushMessage.fromData(const {'deep_link': ' '}).deepLink, isNull);
    });

    test('a tapped push: app_opened + clicked, link parked for MainScreen',
        () async {
      final messaging = _FakeMessaging();
      final container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authTokenStorageProvider.overrideWithValue(_SignedIn(prefs: prefs)),
        notificationsRemoteDataSourceProvider.overrideWithValue(remote),
        pushMessagingProvider.overrideWithValue(messaging),
        pushAppVersionProvider.overrideWithValue(() async => '1.0.26'),
      ]);
      addTearDown(container.dispose);

      await container.read(pushControllerProvider).start();
      messaging.opened.add(
        const PushMessage(notificationId: '01JD', deepLink: '/practice'),
      );
      await pumpEventQueue();

      expect(container.read(pendingNotificationLinkProvider), '/practice');
      final recorded = [
        for (final batch in remote.eventBatches) ...batch,
        ...container.read(notificationEventQueueProvider).pending,
      ].where((e) => e.notificationId == '01JD').map((e) => e.type);
      expect(
        recorded,
        unorderedEquals([
          NotificationEventType.appOpened,
          NotificationEventType.clicked,
        ]),
      );
    });

    test('a tapped push without a link parks the dashboard', () async {
      final messaging = _FakeMessaging();
      final container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authTokenStorageProvider.overrideWithValue(_SignedIn(prefs: prefs)),
        notificationsRemoteDataSourceProvider.overrideWithValue(remote),
        pushMessagingProvider.overrideWithValue(messaging),
        pushAppVersionProvider.overrideWithValue(() async => '1.0.26'),
      ]);
      addTearDown(container.dispose);

      await container.read(pushControllerProvider).start();
      messaging.opened.add(const PushMessage(notificationId: '01JE'));
      await pumpEventQueue();

      expect(container.read(pendingNotificationLinkProvider), '/dash');
    });
  });
}
