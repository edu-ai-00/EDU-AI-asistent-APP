// NOTIF-4 — the Novinky feed: cursor pagination over `/api/feed`, the pages
// kept for offline, the logout wipe, and the old news list for a server that
// has no feed yet.
//
//   flutter test test/notifications/feed_repository_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eduai/core/notifications/notification_event_queue.dart';
import 'package:eduai/core/notifications/push/push_controller.dart';
import 'package:eduai/core/providers/core_providers.dart';
import 'package:eduai/core/providers/notification_providers.dart';
import 'package:eduai/data/repositories/feed_repository.dart';
import 'package:eduai/data/repositories/news_repository.dart';
import 'package:eduai/models/news_model.dart';
import 'package:eduai/routing/deep_link.dart';

import 'fake_notifications_remote.dart';

class _FakeNews implements NewsRepository {
  final List<NewsItem> items;
  _FakeNews(this.items);

  @override
  Future<({List<NewsItem> items, int unreadCount})> fetchList() async =>
      (items: items, unreadCount: items.where((i) => !i.isRead).length);

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

DateTime _at(int minutesAgo) =>
    DateTime.utc(2026, 10, 7, 12).subtract(Duration(minutes: minutesAgo));

/// 45 rows, newest first, alternating notifications and news.
List<Map<String, dynamic>> _rows(int count) => [
      for (var i = 0; i < count; i++)
        i.isEven
            ? notificationRow('01J$i', title: 'Oznámení $i', createdAt: _at(i))
            : newsRow(i, title: 'Novinka $i', createdAt: _at(i)),
    ];

void main() {
  late SharedPreferences prefs;
  late FakeNotificationsRemote remote;
  late FeedRepository repository;
  var authenticated = true;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    remote = FakeNotificationsRemote()
      ..feedRows = _rows(45)
      ..pageUnreadCount = 7;
    authenticated = true;
    repository = FeedRepository(
      remote,
      _FakeNews([]),
      prefs,
      isAuthenticated: () => authenticated,
    );
  });

  group('pagination', () {
    test('first page: 20 rows, the unread count and a cursor', () async {
      final first = await repository.fetchFirstPage();

      expect(first.fromCache, isFalse);
      expect(first.legacy, isFalse);
      expect(first.page.items, hasLength(20));
      expect(first.page.items.first.title, 'Oznámení 0');
      expect(first.page.unreadCount, 7);
      expect(first.page.hasMore, isTrue);
      expect(remote.feedCalls.single.before, isNull);
      expect(remote.feedCalls.single.limit, FeedRepository.pageSize);
    });

    test('next pages send the cursor back verbatim until the end', () async {
      final first = await repository.fetchFirstPage();
      final second = await repository.fetchNextPage(
        before: first.page.nextBefore!,
        beforeId: first.page.nextBeforeId,
      );
      final third = await repository.fetchNextPage(
        before: second.nextBefore!,
        beforeId: second.nextBeforeId,
      );

      expect(remote.feedCalls[1].before, first.page.nextBefore);
      expect(remote.feedCalls[1].beforeId, first.page.nextBeforeId);
      expect(second.items.first.title, 'Oznámení 20');
      expect(third.items, hasLength(5));
      expect(third.hasMore, isFalse);
      expect(third.nextBefore, isNull);
    });

    test('a failed next page throws (the screen offers a retry)', () async {
      final first = await repository.fetchFirstPage();
      remote.offline = true;

      await expectLater(
        repository.fetchNextPage(before: first.page.nextBefore!),
        throwsException,
      );
    });
  });

  group('offline cache', () {
    test('offline: the pages loaded last time, with no next page', () async {
      final first = await repository.fetchFirstPage();
      await repository.fetchNextPage(
        before: first.page.nextBefore!,
        beforeId: first.page.nextBeforeId,
      );

      remote.offline = true;
      final offline = await FeedRepository(remote, _FakeNews([]), prefs)
          .fetchFirstPage(); // a fresh instance: survives an app restart

      expect(offline.fromCache, isTrue);
      expect(offline.page.items, hasLength(40));
      expect(offline.page.items.first.title, 'Oznámení 0');
      expect(offline.page.hasMore, isFalse);
      expect(offline.page.unreadCount, 40, reason: 'all unread in the fixture');
    });

    test('a fresh first page replaces what was kept', () async {
      final first = await repository.fetchFirstPage();
      await repository.fetchNextPage(
        before: first.page.nextBefore!,
        beforeId: first.page.nextBeforeId,
      );
      await repository.fetchFirstPage();

      expect(repository.readCache()!.items, hasLength(20));
    });

    test('offline with nothing kept: the error comes through', () async {
      remote.offline = true;

      await expectLater(repository.fetchFirstPage(), throwsException);
    });

    test('read state reaches the kept copy', () async {
      await repository.fetchFirstPage();

      repository.updateCachedReadState((item) => item.notificationId == '01J0');
      await repository.markAllRead();

      expect(repository.readCache()!.items.every((i) => i.isRead), isTrue);
      expect(remote.readAllCalls, 1);
    });

    test('at most five pages are kept', () async {
      remote.feedRows = _rows(150);
      var page = (await repository.fetchFirstPage()).page;
      while (page.hasMore) {
        page = await repository.fetchNextPage(
          before: page.nextBefore!,
          beforeId: page.nextBeforeId,
        );
      }

      final kept = repository.readCache()!;
      expect(kept.items, hasLength(FeedRepository.maxCachedItems));
      expect(kept.hasMore, isFalse);
    });

    test('a page landing after logout is not written back', () async {
      authenticated = false;
      await repository.fetchFirstPage();

      expect(prefs.getString(FeedRepository.cacheKey), isNull);
    });

    test('logout drops the kept feed', () async {
      await repository.fetchFirstPage();

      await FeedRepository.clearCache(prefs);
      remote.offline = true;

      await expectLater(repository.fetchFirstPage(), throwsException);
    });
  });

  test('a server without /api/feed gets the old news list', () async {
    remote.failStatus = 404;
    repository = FeedRepository(
      remote,
      _FakeNews([
        NewsItem(
          id: 5,
          title: 'Stará novinka',
          perex: 'perex',
          publishedAt: DateTime.utc(2026, 9, 1),
          isRead: false,
        ),
      ]),
      prefs,
    );

    final result = await repository.fetchFirstPage();

    expect(result.legacy, isTrue);
    expect(result.page.items.single.newsId, 5);
    expect(result.page.unreadCount, 1);
    expect(result.page.hasMore, isFalse);
  });

  test('logout clears everything notifications keep for the account',
      () async {
    await repository.fetchFirstPage();
    final queue = NotificationEventQueue(prefs);
    await queue.record('01J0', NotificationEventType.viewed);
    await prefs.setString(PushController.primingChoiceKey, 'declined');
    await prefs.setString(PushController.registeredTokenKey, 'tok');
    await prefs.setString(NotificationTimezoneSync.sentKey, 'Europe/Prague');

    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      notificationEventQueueProvider.overrideWithValue(queue),
    ]);
    addTearDown(container.dispose);
    container.read(unreadNewsCountProvider.notifier).set(4);
    container.read(pendingNotificationLinkProvider.notifier).state = '/quiz';

    final clear = FutureProvider((ref) => clearNotificationLocalState(ref));
    await container.read(clear.future);

    expect(prefs.getString(FeedRepository.cacheKey), isNull);
    expect(queue.pending, isEmpty);
    expect(prefs.containsKey(NotificationEventQueue.recordedKey), isFalse);
    expect(prefs.getString(PushController.primingChoiceKey), isNull);
    expect(prefs.getString(PushController.registeredTokenKey), isNull);
    expect(prefs.getString(NotificationTimezoneSync.sentKey), isNull);
    expect(container.read(unreadNewsCountProvider), 0);
    expect(container.read(pendingNotificationLinkProvider), isNull);
  });
}
