// NOTIF-4 — the Novinky badge counts news *and* notifications, from
// `GET /api/notifications/unread-count` (spec §8). Against a server that
// predates the notification system (404) it must keep working the old way —
// the news list's unread count.
//
//   flutter test test/notifications/unread_badge_test.dart
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eduai/core/providers/core_providers.dart';
import 'package:eduai/core/providers/notification_providers.dart';
import 'package:eduai/data/repositories/feed_repository.dart';
import 'package:eduai/data/repositories/news_repository.dart';
import 'package:eduai/models/news_model.dart';

import 'fake_notifications_remote.dart';

class _FakeNews implements NewsRepository {
  int fetches = 0;

  @override
  Future<({List<NewsItem> items, int unreadCount})> fetchList() async {
    fetches++;
    return (items: <NewsItem>[], unreadCount: 2);
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeNotificationsRemote remote;
  late _FakeNews news;
  late ProviderContainer container;

  setUp(() {
    remote = FakeNotificationsRemote()..unreadCount = 5;
    news = _FakeNews();
    container = ProviderContainer(overrides: [
      notificationsRemoteDataSourceProvider.overrideWithValue(remote),
      newsRepositoryProvider.overrideWithValue(news),
    ]);
    addTearDown(container.dispose);
  });

  test('reads the combined count from the notifications endpoint', () async {
    await container.read(unreadNewsCountProvider.notifier).refresh();

    expect(container.read(unreadNewsCountProvider), 5);
    expect(news.fetches, 0, reason: 'the news list is not needed for it');
  });

  test('an older API (404) falls back to the news list', () async {
    remote.unreadStatus = 404;

    await container.read(unreadNewsCountProvider.notifier).refresh();

    expect(container.read(unreadNewsCountProvider), 2);
    expect(news.fetches, 1);
  });

  test('offline keeps the last known count', () async {
    container.read(unreadNewsCountProvider.notifier).set(3);
    remote.offline = true;

    await container.read(unreadNewsCountProvider.notifier).refresh();

    expect(container.read(unreadNewsCountProvider), 3);
    expect(news.fetches, 0);
  });

  test('offline on a cold start: the count from the feed kept for offline',
      () async {
    SharedPreferences.setMockInitialValues({
      FeedRepository.cacheKey: jsonEncode({
        'data': [
          newsRow(1, createdAt: DateTime.utc(2026, 10, 1)),
          notificationRow('01JA', createdAt: DateTime.utc(2026, 10, 2)),
          notificationRow('01JB',
              createdAt: DateTime.utc(2026, 10, 3), isRead: true),
        ],
        'meta': {'unread_count': 2},
      }),
    });
    final prefs = await SharedPreferences.getInstance();
    final offline = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      notificationsRemoteDataSourceProvider
          .overrideWithValue(FakeNotificationsRemote()..offline = true),
      newsRepositoryProvider.overrideWithValue(news),
    ]);
    addTearDown(offline.dispose);

    await offline.read(unreadNewsCountProvider.notifier).refresh();

    expect(offline.read(unreadNewsCountProvider), 2);
  });

  test('a server error (not 404) does not fall back either', () async {
    container.read(unreadNewsCountProvider.notifier).set(1);
    remote.unreadStatus = 500;

    await container.read(unreadNewsCountProvider.notifier).refresh();

    expect(container.read(unreadNewsCountProvider), 1);
    expect(news.fetches, 0);
  });
}
