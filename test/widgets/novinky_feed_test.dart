// NOTIF-3/4 — Novinky is the notification feed: news and notifications in one
// list with unread dots, "Označit vše jako přečtené", infinite scroll, the
// pages kept for offline, `viewed`/`clicked` events, and the in-app push
// priming card (never an OS prompt at first launch).
//
//   flutter test test/widgets/novinky_feed_test.dart
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eduai/core/notifications/notification_event_queue.dart';
import 'package:eduai/core/services/auth_token_storage.dart';
import 'package:eduai/core/notifications/push/push_controller.dart';
import 'package:eduai/core/notifications/push/push_messaging.dart';
import 'package:eduai/core/providers/core_providers.dart';
import 'package:eduai/core/providers/navigation_providers.dart';
import 'package:eduai/core/providers/notification_providers.dart';
import 'package:eduai/core/strings/app_strings.dart';
import 'package:eduai/data/repositories/feed_repository.dart';
import 'package:eduai/data/repositories/news_repository.dart';
import 'package:eduai/models/news_model.dart';
import 'package:eduai/pages/notification_detail_page.dart';
import 'package:eduai/pages/novinky_page.dart';

import '../notifications/fake_notifications_remote.dart';

class _FakeNewsRepository implements NewsRepository {
  @override
  Future<NewsItem> fetchDetail(int id) async => NewsItem(
        id: id,
        title: 'Novinka $id',
        perex: 'perex',
        body: 'tělo',
        publishedAt: DateTime(2026, 10, 1),
        isRead: false,
      );

  @override
  Future<int> markRead(int id) async => 0;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A signed-in session, without secure storage or network.
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

/// Push available, permission not granted yet (Android 13+ reports that as
/// denied).
class _FakeMessaging implements PushMessaging {
  PushAuthorization status = PushAuthorization.denied;
  PushAuthorization answer = PushAuthorization.authorized;
  int permissionRequests = 0;

  @override
  Future<bool> initialize() async => true;
  @override
  Future<PushAuthorization> authorization() async => status;
  @override
  Future<PushAuthorization> requestPermission() async {
    permissionRequests++;
    status = answer;
    return answer;
  }

  @override
  Future<String?> getToken() async => 'fcm-token';
  @override
  Future<void> deleteToken() async {}
  @override
  Stream<String> get onTokenRefresh => const Stream.empty();
  @override
  Stream<PushMessage> get onForegroundMessage => const Stream.empty();
  @override
  Stream<PushMessage> get onMessageOpenedApp => const Stream.empty();
  @override
  Future<PushMessage?> getInitialMessage() async => null;
}

/// Whether [span] holds a tappable run whose text is [url].
bool _hasLink(InlineSpan span, String url) {
  var found = false;
  span.visitChildren((child) {
    if (child is TextSpan &&
        child.recognizer is TapGestureRecognizer &&
        child.toPlainText().contains(url)) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

DateTime _at(int minutesAgo) =>
    DateTime.utc(2026, 10, 7, 12).subtract(Duration(minutes: minutesAgo));

late FakeNotificationsRemote _remote;
late SharedPreferences _prefs;
late ProviderContainer _container;

Future<void> _pump(
  WidgetTester tester, {
  required List<Map<String, dynamic>> rows,
  int unread = 0,
  PushMessaging? messaging,
  void Function(SharedPreferences prefs)? seed,
  bool offline = false,
}) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  _prefs = await SharedPreferences.getInstance();
  seed?.call(_prefs);
  _remote = FakeNotificationsRemote()
    ..feedRows = rows
    ..pageUnreadCount = unread
    ..unreadCount = unread
    ..offline = offline;
  final news = _FakeNewsRepository();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(_prefs),
        authTokenStorageProvider.overrideWithValue(_SignedIn(prefs: _prefs)),
        newsRepositoryProvider.overrideWithValue(news),
        notificationsRemoteDataSourceProvider.overrideWithValue(_remote),
        feedRepositoryProvider.overrideWithValue(
          FeedRepository(_remote, news, _prefs),
        ),
        pushMessagingProvider.overrideWithValue(messaging),
        pushAppVersionProvider.overrideWithValue(() async => '1.0.26'),
      ],
      child: const MaterialApp(home: Scaffold(body: NovinkyPage())),
    ),
  );
  await tester.pump();
  await tester.pump();
  _container = ProviderScope.containerOf(tester.element(find.byType(NovinkyPage)));
}

/// Everything recorded so far: sent already, or still queued.
List<NotificationEvent> get _queued => [
      for (final batch in _remote.eventBatches) ...batch,
      ..._container.read(notificationEventQueueProvider).pending,
    ];

final _mixed = [
  notificationRow('01JA', title: 'Kurz dokončen', deepLink: '/courses', createdAt: _at(0)),
  newsRow(7, title: 'Nová lekce', createdAt: _at(5)),
  notificationRow('01JB', title: 'Cíl splněn!', createdAt: _at(10), isRead: true),
];

void main() {
  testWidgets('shows news and notifications in one list, newest first',
      (tester) async {
    await _pump(tester, rows: _mixed, unread: 2);

    final kurz = tester.getTopLeft(find.text('Kurz dokončen')).dy;
    final lekce = tester.getTopLeft(find.text('Nová lekce')).dy;
    final cil = tester.getTopLeft(find.text('Cíl splněn!')).dy;
    expect(kurz, lessThan(lekce));
    expect(lekce, lessThan(cil));

    // Notifications carry their category icon, news does not.
    expect(find.byIcon(Icons.emoji_events_outlined), findsNWidgets(2));
    // The badge follows the feed's unread count.
    expect(_container.read(unreadNewsCountProvider), 2);
  });

  testWidgets('"Označit vše jako přečtené" clears every dot and the badge',
      (tester) async {
    await _pump(tester, rows: _mixed, unread: 2);
    expect(find.byKey(NovinkyPage.markAllReadKey), findsOneWidget);

    await tester.tap(find.byKey(NovinkyPage.markAllReadKey));
    await tester.pump();
    await tester.pump();

    expect(_remote.readAllCalls, 1);
    final feed = _container.read(feedControllerProvider).value!;
    expect(feed.items.every((i) => i.isRead), isTrue);
    expect(_container.read(unreadNewsCountProvider), 0);
    // Nothing left to mark.
    expect(find.byKey(NovinkyPage.markAllReadKey), findsNothing);
  });

  testWidgets('a failed "mark all" brings the dots back', (tester) async {
    await _pump(tester, rows: _mixed, unread: 2);
    _remote.readAllFails = true;

    await tester.tap(find.byKey(NovinkyPage.markAllReadKey));
    await tester.pump();
    await tester.pump();

    final feed = _container.read(feedControllerProvider).value!;
    expect(feed.items.where((i) => !i.isRead).map((i) => i.id),
        ['01JA', 'news-7']);
    expect(find.text(AppStrings.novinkyMarkAllReadFailed), findsOneWidget);
  });

  testWidgets('notification rows are reported viewed once', (tester) async {
    await _pump(tester, rows: _mixed, unread: 2);

    final viewed = _queued
        .where((e) => e.type == NotificationEventType.viewed)
        .map((e) => e.notificationId)
        .toList();
    expect(viewed, unorderedEquals(['01JA', '01JB']));

    // A rebuild does not report them again.
    await tester.drag(find.byType(ListView), const Offset(0, -20));
    await tester.pump();
    expect(
      _queued.where((e) => e.type == NotificationEventType.viewed),
      hasLength(2),
    );
  });

  testWidgets('tapping a notification: clicked, read, and its link opens',
      (tester) async {
    await _pump(tester, rows: _mixed, unread: 2);

    await tester.tap(find.text('Kurz dokončen'));
    await tester.pump();
    await tester.pump();

    expect(
      _queued.any((e) =>
          e.notificationId == '01JA' && e.type == NotificationEventType.clicked),
      isTrue,
    );
    expect(_remote.readCalls, ['01JA']);
    final item = _container
        .read(feedControllerProvider)
        .value!
        .items
        .firstWhere((i) => i.id == '01JA');
    expect(item.isRead, isTrue);
    // deep_link '/courses' → the Kurzy tab.
    expect(_container.read(mainTabIndexProvider), 3);
  });

  // BR-MCEHBH: a school message's link is Novinky itself, so following it went
  // nowhere and the text never got past the card's three-line preview.
  testWidgets('a notification linking to Novinky opens its full text',
      (tester) async {
    const body = 'Řádek 1\nŘádek 2\nŘádek 3\nŘádek 4\n'
        'Projděte si kvíz zde: https://app-stage.edu-ai.eu/pin/654321';
    await _pump(tester, unread: 1, rows: [
      notificationRow('01JM',
          title: 'Dnes je potřeba dokončit test',
          body: body,
          deepLink: '/news',
          category: 'provoz',
          createdAt: _at(0)),
      newsRow(7, title: 'Nová lekce', createdAt: _at(5)),
    ]);
    _container.read(mainTabIndexProvider.notifier).state = 4;

    await tester.tap(find.text('Dnes je potřeba dokončit test'));
    await tester.pumpAndSettle();

    // A page of its own, over the feed, with the whole message.
    final detail = tester
        .widget<NotificationDetailPage>(find.byType(NotificationDetailPage));
    expect(detail.embedded, isFalse);
    expect(detail.item.body, body);
    expect(find.text('Nová lekce'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(NotificationDetailPage),
        matching: find.textContaining('Řádek 4', findRichText: true),
      ),
      findsOneWidget,
    );
    // The link in the text is a link, not plain text.
    expect(
      find.descendant(
        of: find.byType(NotificationDetailPage),
        // Selectable markdown renders as SelectableText.rich.
        matching: find.byWidgetPredicate((w) {
          final span = switch (w) {
            SelectableText(:final textSpan) => textSpan,
            RichText(:final text) => text,
            _ => null,
          };
          return span != null &&
              _hasLink(span, 'https://app-stage.edu-ai.eu/pin/654321');
        }),
      ),
      findsOneWidget,
    );

    // Still counts as opened: clicked, read, and Novinky stays the tab.
    expect(
      _queued.any((e) =>
          e.notificationId == '01JM' && e.type == NotificationEventType.clicked),
      isTrue,
    );
    expect(_remote.readCalls, ['01JM']);
    expect(_container.read(mainTabIndexProvider), 4);
  });

  testWidgets('scrolling to the end loads the next page', (tester) async {
    await _pump(tester, rows: [
      for (var i = 0; i < 30; i++)
        notificationRow('01J$i', title: 'Oznámení $i', createdAt: _at(i)),
    ]);
    expect(_remote.feedCalls, hasLength(1));

    await tester.dragUntilVisible(
      find.text('Oznámení 25'),
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.pump();

    expect(_remote.feedCalls.length, greaterThanOrEqualTo(2));
    expect(_remote.feedCalls[1].before, isNotNull);
    expect(_container.read(feedControllerProvider).value!.items, hasLength(30));
  });

  testWidgets('offline: the kept pages under a hint', (tester) async {
    await _pump(
      tester,
      rows: _mixed,
      offline: true,
      seed: (prefs) => prefs.setString(
        FeedRepository.cacheKey,
        '{"data":[${'{"kind":"news","id":"news-3","news_id":3,"title":"Uložená novinka","body":"x","created_at":"2026-10-01T08:00:00Z","is_read":false}'}],"meta":{"unread_count":1}}',
      ),
    );

    expect(find.text('Uložená novinka'), findsOneWidget);
    expect(find.text(AppStrings.novinkyOfflineHint), findsOneWidget);
  });

  testWidgets('no push available: no priming card', (tester) async {
    await _pump(tester, rows: _mixed);

    expect(find.text(AppStrings.pushPrimingTitle), findsNothing);
  });

  testWidgets('priming card: "Teď ne" hides it for good, no OS prompt',
      (tester) async {
    final messaging = _FakeMessaging();
    await _pump(tester, rows: _mixed, messaging: messaging);
    expect(find.text(AppStrings.pushPrimingTitle), findsOneWidget);
    expect(messaging.permissionRequests, 0, reason: 'never at first sight');

    await tester.tap(find.byKey(NovinkyPage.primingLaterKey));
    await tester.pump();
    await tester.pump();

    expect(find.text(AppStrings.pushPrimingTitle), findsNothing);
    expect(_prefs.getString(PushController.primingChoiceKey), 'declined');
    expect(messaging.permissionRequests, 0);
  });

  testWidgets('priming card: "Povolit" asks the OS and registers the token',
      (tester) async {
    final messaging = _FakeMessaging();
    await _pump(tester, rows: _mixed, messaging: messaging);

    expect(_container.read(pushControllerProvider).isAvailable, isTrue);

    await tester.tap(find.byKey(NovinkyPage.primingAllowKey));
    await tester.pumpAndSettle();

    expect(messaging.permissionRequests, 1);
    expect(_prefs.getString(PushController.primingChoiceKey), 'accepted');
    expect(find.text(AppStrings.pushPrimingTitle), findsNothing);
    final device = _remote.registeredDevices.single;
    expect(device.token, 'fcm-token');
    expect(device.platform, 'android'); // the test platform
    expect(_prefs.getString(PushController.registeredTokenKey), 'fcm-token');
  });

  testWidgets('an answered card does not come back', (tester) async {
    await _pump(
      tester,
      rows: _mixed,
      messaging: _FakeMessaging(),
      seed: (prefs) =>
          unawaited(prefs.setString(PushController.primingChoiceKey, 'declined')),
    );

    expect(find.text(AppStrings.pushPrimingTitle), findsNothing);
  });
}
