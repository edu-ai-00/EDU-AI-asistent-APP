import 'news_model.dart';

/// What a [FeedItem] is: a published news article, or a notification sent to
/// this user (NOTIF-4). The two share one list — Novinky *is* the
/// notification feed (BR-KN9XUT), there is no separate inbox.
enum FeedItemKind { notification, news }

/// One row of `GET /api/feed`.
///
/// News rows open [NewsDetailPage] by [newsId] exactly as before; notification
/// rows carry a [deepLink] the app resolves itself and a [notificationId] the
/// read/event endpoints are keyed by.
class FeedItem {
  final FeedItemKind kind;

  /// Unique across both kinds (`"01J…"` for a notification, `"news-12"` for
  /// an article) — what the list dedupes pages by.
  final String id;

  /// Public ULID of the notification. Null for news.
  final String? notificationId;

  /// `news.id`, for the detail endpoint. Null for notifications.
  final int? newsId;

  final String? typeKey;
  final String? category;
  final String title;

  /// Notification text, or the article's perex.
  final String body;

  /// In-app path such as `/course/ABC123`. Null for news.
  final String? deepLink;

  final DateTime createdAt;
  final bool isRead;

  const FeedItem({
    required this.kind,
    required this.id,
    this.notificationId,
    this.newsId,
    this.typeKey,
    this.category,
    required this.title,
    required this.body,
    this.deepLink,
    required this.createdAt,
    required this.isRead,
  });

  bool get isNotification => kind == FeedItemKind.notification;
  bool get isNews => kind == FeedItemKind.news;

  /// Parse one feed row, or null when it cannot be shown or acted on — an
  /// unknown `kind` from a newer server, a missing id or an unreadable date.
  /// A single odd row must not take the whole feed down with it.
  static FeedItem? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);

    final kind = switch (json['kind']) {
      'notification' => FeedItemKind.notification,
      'news' => FeedItemKind.news,
      _ => null,
    };
    if (kind == null) return null;

    final createdAt = _parseDate(json['created_at']);
    if (createdAt == null) return null;

    final rawId = _string(json['id']);
    final title = _string(json['title']) ?? '';
    final body = _string(json['body']) ?? '';
    final isRead = _bool(json['is_read']);

    switch (kind) {
      case FeedItemKind.notification:
        final notificationId = _string(json['notification_id']) ?? rawId;
        if (notificationId == null || notificationId.isEmpty) return null;
        return FeedItem(
          kind: kind,
          id: rawId ?? notificationId,
          notificationId: notificationId,
          typeKey: _string(json['type_key']),
          category: _string(json['category']),
          title: title,
          body: body,
          deepLink: _string(json['deep_link']),
          createdAt: createdAt,
          isRead: isRead,
        );
      case FeedItemKind.news:
        final newsId = _int(json['news_id']) ?? _newsIdFrom(rawId);
        if (newsId == null) return null;
        return FeedItem(
          kind: kind,
          id: rawId ?? 'news-$newsId',
          newsId: newsId,
          title: title,
          body: body,
          deepLink: _string(json['deep_link']),
          createdAt: createdAt,
          isRead: isRead,
        );
    }
  }

  /// An article from the old `/api/news` list, for servers that do not have
  /// `/api/feed` yet.
  factory FeedItem.fromNews(NewsItem item) => FeedItem(
        kind: FeedItemKind.news,
        id: 'news-${item.id}',
        newsId: item.id,
        title: item.title,
        body: item.perex,
        createdAt: item.publishedAt,
        isRead: item.isRead,
      );

  /// Same shape as the API row, so the offline copy reads back through
  /// [tryParse].
  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'id': id,
        if (notificationId != null) 'notification_id': notificationId,
        if (newsId != null) 'news_id': newsId,
        if (typeKey != null) 'type_key': typeKey,
        if (category != null) 'category': category,
        'title': title,
        'body': body,
        'deep_link': deepLink,
        'created_at': createdAt.toIso8601String(),
        'is_read': isRead,
      };

  FeedItem copyWith({bool? isRead}) => FeedItem(
        kind: kind,
        id: id,
        notificationId: notificationId,
        newsId: newsId,
        typeKey: typeKey,
        category: category,
        title: title,
        body: body,
        deepLink: deepLink,
        createdAt: createdAt,
        isRead: isRead ?? this.isRead,
      );

  static String? _string(Object? value) {
    if (value == null) return null;
    if (value is String) return value;
    if (value is num) return value.toString();
    return null;
  }

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static bool _bool(Object? value) =>
      value == true || value == 1 || value == '1' || value == 'true';

  static DateTime? _parseDate(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  /// `"news-12"` → 12, for a row that left out `news_id`.
  static int? _newsIdFrom(String? id) {
    if (id == null) return null;
    final match = RegExp(r'^news-(\d+)$').firstMatch(id);
    return match == null ? null : int.tryParse(match.group(1)!);
  }
}

/// One page of `GET /api/feed` with its `meta`.
class FeedPage {
  final List<FeedItem> items;
  final int unreadCount;

  /// Cursor for the next page — sent back verbatim as `before` (and
  /// `before_id` when the server supplied one).
  final String? nextBefore;
  final String? nextBeforeId;
  final bool hasMore;

  const FeedPage({
    required this.items,
    required this.unreadCount,
    this.nextBefore,
    this.nextBeforeId,
    required this.hasMore,
  });

  static const empty = FeedPage(items: [], unreadCount: 0, hasMore: false);

  /// Parse the whole response body (`{data: [...], meta: {...}}`).
  factory FeedPage.fromResponse(Map<String, dynamic> body) {
    final data = body['data'];
    final items = <FeedItem>[
      if (data is List)
        for (final row in data) ?FeedItem.tryParse(row),
    ];

    final meta = body['meta'] is Map
        ? Map<String, dynamic>.from(body['meta'] as Map)
        : const <String, dynamic>{};
    final nextBefore = FeedItem._string(meta['next_before']);
    final nextBeforeId = FeedItem._string(meta['next_before_id']);
    final hasMore = meta.containsKey('has_more')
        ? FeedItem._bool(meta['has_more'])
        : nextBefore != null;

    return FeedPage(
      items: items,
      unreadCount: FeedItem._int(meta['unread_count']) ?? 0,
      nextBefore: nextBefore,
      nextBeforeId: nextBeforeId,
      // No cursor, no next page — whatever has_more says.
      hasMore: hasMore && nextBefore != null,
    );
  }
}
