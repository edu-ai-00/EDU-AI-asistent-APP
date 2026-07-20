import '../datasources/remote/news_remote_datasource.dart';
import '../../models/news_model.dart';

/// Thin pass-through repository for news. Online-only.
class NewsRepository {
  final NewsRemoteDataSource _remoteDataSource;

  NewsRepository(this._remoteDataSource);

  /// Fetch the news list along with the unread count.
  Future<({List<NewsItem> items, int unreadCount})> fetchList() async {
    final result = await _remoteDataSource.getNews();
    if (result.isFailure) throw Exception(result.error);
    return result.data!;
  }

  /// Fetch a single news item (with body).
  Future<NewsItem> fetchDetail(int id) async {
    final result = await _remoteDataSource.getNewsItem(id);
    if (result.isFailure) throw Exception(result.error);
    return result.data!;
  }

  /// Mark a news item as read; returns the updated unread count.
  Future<int> markRead(int id) async {
    final result = await _remoteDataSource.markRead(id);
    if (result.isFailure) throw Exception(result.error);
    return result.data!;
  }
}
