/// A single news item ("Novinka").
///
/// `body` is null in list responses (only metadata) and populated in the
/// detail response.
class NewsItem {
  final int id;
  final String title;
  final String perex;
  final String? body;
  final DateTime publishedAt;
  final bool isRead;

  NewsItem({
    required this.id,
    required this.title,
    required this.perex,
    this.body,
    required this.publishedAt,
    required this.isRead,
  });

  factory NewsItem.fromJson(Map<String, dynamic> json) {
    return NewsItem(
      id: json['id'] as int,
      title: json['title'] as String? ?? '',
      perex: json['perex'] as String? ?? '',
      body: json['body'] as String?,
      publishedAt: DateTime.parse(json['published_at'] as String),
      isRead: json['is_read'] as bool? ?? false,
    );
  }

  NewsItem copyWith({bool? isRead}) {
    return NewsItem(
      id: id,
      title: title,
      perex: perex,
      body: body,
      publishedAt: publishedAt,
      isRead: isRead ?? this.isRead,
    );
  }
}
