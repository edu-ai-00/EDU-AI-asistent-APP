import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/feed_item.dart';
import '../datasources/remote/notifications_remote_datasource.dart';
import 'news_repository.dart';

/// A page as the feed screen gets it.
class FeedFetchResult {
  final FeedPage page;

  /// Served from the copy kept for offline because the server could not be
  /// reached.
  final bool fromCache;

  /// The server has no `/api/feed` yet; [page] is the old news list.
  final bool legacy;

  const FeedFetchResult(
    this.page, {
    this.fromCache = false,
    this.legacy = false,
  });
}

/// Repository for the Novinky feed — news and notifications in one list
/// (NOTIF-4).
///
/// Network first, like [NewsRepository]: the pages loaded last time are kept
/// in SharedPreferences, so offline the feed shows them instead of an error.
/// They carry this account's read state, so logout drops them ([clearCache]).
///
/// A server without `/api/feed` (404) still gets a working Novinky: the feed
/// falls back to the old news list.
class FeedRepository {
  static const String cacheKey = 'notification_feed_cache_v1';

  /// Page size the feed asks for.
  static const int pageSize = 20;

  /// How much of the feed is kept for offline — the first five pages.
  static const int maxCachedItems = 100;

  final NotificationsRemoteDataSource _remote;
  final NewsRepository _news;
  final SharedPreferences _prefs;

  /// Whether a session is signed in. A page that lands after logout has
  /// cleared the cache must not write the previous account's feed back.
  final bool Function() _isAuthenticated;

  FeedRepository(
    this._remote,
    this._news,
    this._prefs, {
    bool Function()? isAuthenticated,
  }) : _isAuthenticated = isAuthenticated ?? (() => true);

  /// Drops the kept feed. Called from the logout teardown.
  static Future<void> clearCache(SharedPreferences prefs) async {
    await prefs.remove(cacheKey);
  }

  /// The newest page — or, when the network fails, what was kept last time.
  /// Throws only when there is nothing to show.
  Future<FeedFetchResult> fetchFirstPage() async {
    final result = await _remote.getFeed(limit: pageSize);
    if (result.isSuccess) {
      _writeCache(result.data!);
      return FeedFetchResult(result.data!);
    }

    if (result.statusCode == 404) {
      final news = await _news.fetchList();
      return FeedFetchResult(
        FeedPage(
          items: [for (final item in news.items) FeedItem.fromNews(item)],
          unreadCount: news.unreadCount,
          hasMore: false,
        ),
        legacy: true,
      );
    }

    final kept = readCache();
    if (kept == null) throw Exception(result.error);
    // Nothing more can be fetched offline; the next refresh starts over.
    return FeedFetchResult(
      FeedPage(
        items: kept.items,
        unreadCount: kept.items.where((i) => !i.isRead).length,
        hasMore: false,
      ),
      fromCache: true,
    );
  }

  /// The page after [before]. Throws on failure — the screen keeps what it
  /// has and offers a retry.
  Future<FeedPage> fetchNextPage({
    required String before,
    String? beforeId,
  }) async {
    final result = await _remote.getFeed(
      before: before,
      beforeId: beforeId,
      limit: pageSize,
    );
    if (result.isFailure) throw Exception(result.error);
    _appendCache(result.data!);
    return result.data!;
  }

  /// Mark one notification read; returns the new unread count.
  Future<int> markRead(String notificationId) async {
    updateCachedReadState((item) => item.notificationId == notificationId);
    final result = await _remote.markRead(notificationId);
    if (result.isFailure) throw Exception(result.error);
    return result.data!;
  }

  /// Mark everything read; returns the new unread count.
  Future<int> markAllRead() async {
    final result = await _remote.markAllRead();
    if (result.isFailure) throw Exception(result.error);
    updateCachedReadState((_) => true);
    return result.data!;
  }

  /// Flip the kept copy of every item matching [test] to read, so an offline
  /// start does not resurrect unread dots the user already cleared.
  void updateCachedReadState(bool Function(FeedItem item) test) {
    final kept = readCache();
    if (kept == null) return;
    if (!kept.items.any((item) => !item.isRead && test(item))) return;
    final items = [
      for (final item in kept.items)
        if (!item.isRead && test(item)) item.copyWith(isRead: true) else item,
    ];
    _saveCache(FeedPage(
      items: items,
      unreadCount: items.where((i) => !i.isRead).length,
      nextBefore: kept.nextBefore,
      nextBeforeId: kept.nextBeforeId,
      hasMore: kept.hasMore,
    ));
  }

  // ── Cache ───────────────────────────────────────────────────────────────

  /// The kept feed, or null when there is none (or it is unreadable).
  FeedPage? readCache() {
    final raw = _prefs.getString(cacheKey);
    if (raw == null) return null;
    try {
      final body = jsonDecode(raw) as Map<String, dynamic>;
      return FeedPage.fromResponse(body);
    } catch (_) {
      // A cache written by an older schema is not worth recovering.
      _prefs.remove(cacheKey);
      return null;
    }
  }

  /// A fresh first page replaces whatever was kept.
  void _writeCache(FeedPage page) => _saveCache(page);

  void _appendCache(FeedPage page) {
    final kept = readCache();
    if (kept == null) return; // no first page to append to
    final ids = {for (final item in kept.items) item.id};
    final items = [
      ...kept.items,
      for (final item in page.items)
        if (!ids.contains(item.id)) item,
    ];
    if (items.length > maxCachedItems) {
      // Beyond the cap the kept copy simply stops; it no longer continues
      // where the cursor points, so it must not claim a next page either.
      _saveCache(FeedPage(
        items: items.take(maxCachedItems).toList(),
        unreadCount: page.unreadCount,
        hasMore: false,
      ));
      return;
    }
    _saveCache(FeedPage(
      items: items,
      unreadCount: page.unreadCount,
      nextBefore: page.nextBefore,
      nextBeforeId: page.nextBeforeId,
      hasMore: page.hasMore,
    ));
  }

  void _saveCache(FeedPage page) {
    if (!_isAuthenticated()) return;
    _prefs.setString(
      cacheKey,
      jsonEncode({
        'data': [
          for (final item in page.items.take(maxCachedItems)) item.toJson(),
        ],
        'meta': {
          'unread_count': page.unreadCount,
          'next_before': page.nextBefore,
          'next_before_id': page.nextBeforeId,
          'has_more': page.hasMore,
        },
      }),
    );
  }
}
