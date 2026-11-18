import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../datasources/remote/news_remote_datasource.dart';
import '../../models/news_model.dart';

/// Repository for news ("Novinky").
///
/// Network first, with a copy kept in SharedPreferences: the last list the
/// server sent and the articles opened from it. Offline the feed shows what
/// it showed last time instead of an error — before, it was online-only and
/// had nothing at all to show without a connection (BR-7XZXZD).
///
/// The copy carries the account's read flags, so logout drops it
/// ([clearCache]) rather than hand them to whoever logs in next.
class NewsRepository {
  static const String _listKey = 'news_list_cache_v1';
  static const String _articlesKey = 'news_articles_cache_v1';

  final NewsRemoteDataSource _remoteDataSource;
  final SharedPreferences _prefs;

  NewsRepository(this._remoteDataSource, this._prefs);

  /// Drops the kept news. Called from the logout teardown.
  static Future<void> clearCache(SharedPreferences prefs) async {
    await prefs.remove(_listKey);
    await prefs.remove(_articlesKey);
  }

  /// Fetch the news list along with the unread count — or, when the network
  /// fails, the list kept from last time. Throws only when there is none.
  Future<({List<NewsItem> items, int unreadCount})> fetchList() async {
    final result = await _remoteDataSource.getNews();
    if (result.isFailure) {
      final kept = _readList();
      if (kept == null) throw Exception(result.error);
      return (
        items: kept,
        unreadCount: kept.where((item) => !item.isRead).length,
      );
    }

    _writeList(result.data!.items);
    return result.data!;
  }

  /// Fetch a single news item (with body) — or, when the network fails, the
  /// copy kept from when it was last opened. An article never opened online
  /// falls back to its list entry, whose perex the detail page shows in place
  /// of the body. Throws only when neither is kept.
  Future<NewsItem> fetchDetail(int id) async {
    final result = await _remoteDataSource.getNewsItem(id);
    if (result.isFailure) {
      final kept = _readArticles()[id] ??
          _readList()?.where((item) => item.id == id).firstOrNull;
      if (kept == null) throw Exception(result.error);
      return kept;
    }

    _writeArticle(result.data!);
    return result.data!;
  }

  /// Mark a news item as read; returns the updated unread count.
  Future<int> markRead(int id) async {
    final result = await _remoteDataSource.markRead(id);
    if (result.isFailure) throw Exception(result.error);
    return result.data!;
  }

  // ── Cache ───────────────────────────────────────────────────────────────

  List<NewsItem>? _readList() {
    final raw = _prefs.getString(_listKey);
    if (raw == null) return null;

    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((json) => NewsItem.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // A cache written by an older schema is not worth recovering.
      _prefs.remove(_listKey);
      return null;
    }
  }

  Map<int, NewsItem> _readArticles() {
    final raw = _prefs.getString(_articlesKey);
    if (raw == null) return {};

    try {
      final items = (jsonDecode(raw) as List<dynamic>)
          .map((json) => NewsItem.fromJson(json as Map<String, dynamic>));
      return {for (final item in items) item.id: item};
    } catch (_) {
      _prefs.remove(_articlesKey);
      return {};
    }
  }

  void _writeList(List<NewsItem> items) {
    _prefs.setString(
      _listKey,
      jsonEncode([for (final item in items) item.toJson()]),
    );

    // Articles that dropped off the feed are not coming back; keeping their
    // bodies would only grow the cache.
    final ids = {for (final item in items) item.id};
    final articles = _readArticles();
    if (articles.keys.every(ids.contains)) return;
    articles.removeWhere((id, _) => !ids.contains(id));
    _writeArticles(articles);
  }

  void _writeArticle(NewsItem item) {
    _writeArticles(_readArticles()..[item.id] = item);
  }

  void _writeArticles(Map<int, NewsItem> articles) {
    _prefs.setString(
      _articlesKey,
      jsonEncode([for (final item in articles.values) item.toJson()]),
    );
  }
}
