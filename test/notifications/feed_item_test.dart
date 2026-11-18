// NOTIF-4 — the Novinky feed mixes news and notifications in one list
// (`GET /api/feed`, spec §5.1). Both row kinds must parse from the documented
// JSON, and a row the app cannot act on must be skipped rather than take the
// whole page down.
//
//   flutter test test/notifications/feed_item_test.dart
import 'package:flutter_test/flutter_test.dart';

import 'package:eduai/models/feed_item.dart';
import 'package:eduai/models/news_model.dart';

void main() {
  group('FeedItem.tryParse', () {
    test('a notification row', () {
      final item = FeedItem.tryParse({
        'kind': 'notification',
        'id': '01JABCDEF',
        'notification_id': '01JABCDEF',
        'type_key': 'course_completed',
        'category': 'pokrok',
        'title': 'Kurz dokončen',
        'body': 'Gratulujeme!',
        'deep_link': '/course/ABC123',
        'created_at': '2026-10-07T10:00:00+00:00',
        'is_read': false,
      })!;

      expect(item.kind, FeedItemKind.notification);
      expect(item.isNotification, isTrue);
      expect(item.id, '01JABCDEF');
      expect(item.notificationId, '01JABCDEF');
      expect(item.newsId, isNull);
      expect(item.typeKey, 'course_completed');
      expect(item.category, 'pokrok');
      expect(item.title, 'Kurz dokončen');
      expect(item.body, 'Gratulujeme!');
      expect(item.deepLink, '/course/ABC123');
      expect(item.createdAt, DateTime.utc(2026, 10, 7, 10));
      expect(item.isRead, isFalse);
    });

    test('a news row', () {
      final item = FeedItem.tryParse({
        'kind': 'news',
        'id': 'news-12',
        'news_id': 12,
        'title': 'Nová lekce',
        'body': '<perex>',
        'deep_link': null,
        'created_at': '2026-10-01T08:00:00+00:00',
        'is_read': true,
      })!;

      expect(item.kind, FeedItemKind.news);
      expect(item.isNews, isTrue);
      expect(item.id, 'news-12');
      expect(item.newsId, 12);
      expect(item.notificationId, isNull);
      expect(item.body, '<perex>');
      expect(item.deepLink, isNull);
      expect(item.isRead, isTrue);
    });

    test('a news row without news_id takes it from the feed id', () {
      final item = FeedItem.tryParse({
        'kind': 'news',
        'id': 'news-7',
        'title': 'x',
        'created_at': '2026-10-01T08:00:00Z',
      })!;

      expect(item.newsId, 7);
    });

    test('a notification row without notification_id uses its id', () {
      final item = FeedItem.tryParse({
        'kind': 'notification',
        'id': '01JX',
        'title': 'x',
        'created_at': '2026-10-01T08:00:00Z',
      })!;

      expect(item.notificationId, '01JX');
      expect(item.isRead, isFalse, reason: 'missing is_read reads as unread');
    });

    test('rows the app cannot show or act on are skipped', () {
      expect(FeedItem.tryParse(null), isNull);
      expect(FeedItem.tryParse('nope'), isNull);
      // A kind from a newer server.
      expect(
        FeedItem.tryParse({
          'kind': 'survey',
          'id': 'x',
          'created_at': '2026-10-01T08:00:00Z',
        }),
        isNull,
      );
      // No usable date.
      expect(
        FeedItem.tryParse({'kind': 'notification', 'id': 'x', 'created_at': 'soon'}),
        isNull,
      );
      // News nobody could open.
      expect(
        FeedItem.tryParse({
          'kind': 'news',
          'id': 'whatever',
          'created_at': '2026-10-01T08:00:00Z',
        }),
        isNull,
      );
    });

    test('toJson reads back through tryParse (the offline copy)', () {
      final original = FeedItem.tryParse({
        'kind': 'notification',
        'id': '01JR',
        'notification_id': '01JR',
        'type_key': 'learning_reminder',
        'category': 'navyk',
        'title': 'Je čas na učení',
        'body': 'Stačí pár minut.',
        'deep_link': '/dash',
        'created_at': '2026-10-07T10:00:00Z',
        'is_read': true,
      })!;

      final copy = FeedItem.tryParse(original.toJson())!;

      expect(copy.id, original.id);
      expect(copy.notificationId, original.notificationId);
      expect(copy.typeKey, original.typeKey);
      expect(copy.category, original.category);
      expect(copy.deepLink, original.deepLink);
      expect(copy.createdAt, original.createdAt);
      expect(copy.isRead, isTrue);
    });

    test('fromNews maps an old /api/news row', () {
      final item = FeedItem.fromNews(NewsItem(
        id: 3,
        title: 'T',
        perex: 'P',
        publishedAt: DateTime.utc(2026, 9, 1),
        isRead: false,
      ));

      expect(item.kind, FeedItemKind.news);
      expect(item.id, 'news-3');
      expect(item.newsId, 3);
      expect(item.body, 'P');
    });
  });

  group('FeedPage.fromResponse', () {
    test('items, unread count and the cursor from meta', () {
      final page = FeedPage.fromResponse({
        'data': [
          {
            'kind': 'notification',
            'id': '01J1',
            'title': 'a',
            'created_at': '2026-10-07T10:00:00Z',
          },
          {'kind': 'mystery', 'id': '?', 'created_at': '2026-10-07T10:00:00Z'},
          {
            'kind': 'news',
            'id': 'news-1',
            'news_id': 1,
            'title': 'b',
            'created_at': '2026-10-06T10:00:00Z',
          },
        ],
        'meta': {
          'unread_count': 3,
          'next_before': '2026-10-06T10:00:00+00:00',
          'next_before_id': 'news-1',
          'has_more': true,
        },
      });

      expect(page.items.map((i) => i.id), ['01J1', 'news-1']);
      expect(page.unreadCount, 3);
      expect(page.nextBefore, '2026-10-06T10:00:00+00:00');
      expect(page.nextBeforeId, 'news-1');
      expect(page.hasMore, isTrue);
    });

    test('no cursor means no next page, whatever has_more says', () {
      final page = FeedPage.fromResponse({
        'data': const [],
        'meta': {'unread_count': 0, 'has_more': true},
      });

      expect(page.hasMore, isFalse);
    });

    test('a numeric next_before_id is kept verbatim as text', () {
      final page = FeedPage.fromResponse({
        'data': const [],
        'meta': {'next_before': '2026-10-01T00:00:00Z', 'next_before_id': 42},
      });

      expect(page.nextBeforeId, '42');
      expect(page.hasMore, isTrue, reason: 'cursor present, has_more absent');
    });
  });
}
