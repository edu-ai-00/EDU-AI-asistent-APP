import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../models/news_model.dart';

/// Remote data source for news ("Novinky"). Online-only — no local storage.
class NewsRemoteDataSource {
  final ApiClient _apiClient;

  NewsRemoteDataSource(this._apiClient);

  /// Fetch the list of news items plus the unread count from meta.
  Future<ApiResult<({List<NewsItem> items, int unreadCount})>> getNews() async {
    final result = await _apiClient.get<Map<String, dynamic>>(
      ApiEndpoints.news,
    );

    if (result.isFailure) {
      return ApiResult.failure(result.error!, statusCode: result.statusCode);
    }

    try {
      final itemsJson = result.data!['data'] as List<dynamic>? ?? [];
      final items = itemsJson
          .map((json) => NewsItem.fromJson(json as Map<String, dynamic>))
          .toList();

      final meta = result.data!['meta'] as Map<String, dynamic>?;
      final unreadCount = meta?['unread_count'] as int? ?? 0;

      return ApiResult.success((items: items, unreadCount: unreadCount));
    } catch (e) {
      return ApiResult.failure('Failed to parse news: $e');
    }
  }

  /// Fetch a single news item (with markdown body).
  Future<ApiResult<NewsItem>> getNewsItem(int id) async {
    final result = await _apiClient.get<Map<String, dynamic>>(
      ApiEndpoints.newsItem(id),
    );

    if (result.isFailure) {
      return ApiResult.failure(result.error!, statusCode: result.statusCode);
    }

    try {
      final itemJson = result.data!['data'] as Map<String, dynamic>;
      return ApiResult.success(NewsItem.fromJson(itemJson));
    } catch (e) {
      return ApiResult.failure('Failed to parse news item: $e');
    }
  }

  /// Mark a news item as read. Returns the updated unread count.
  Future<ApiResult<int>> markRead(int id) async {
    final result = await _apiClient.post<Map<String, dynamic>>(
      ApiEndpoints.newsRead(id),
    );

    if (result.isFailure) {
      return ApiResult.failure(result.error!, statusCode: result.statusCode);
    }

    try {
      final data = result.data!['data'] as Map<String, dynamic>;
      final unreadCount = data['unread_count'] as int? ?? 0;
      return ApiResult.success(unreadCount);
    } catch (e) {
      return ApiResult.failure('Failed to parse read response: $e');
    }
  }
}
