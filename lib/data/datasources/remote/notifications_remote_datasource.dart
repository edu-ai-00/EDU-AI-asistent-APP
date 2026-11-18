import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/notifications/notification_event_queue.dart';
import '../../../models/feed_item.dart';
import '../../../models/notification_preferences.dart';

/// Remote data source for the notification system's app endpoints
/// (docs/superpowers/specs/2026-10-07-notification-system-design.md §5.1):
/// the Novinky feed, read state, event batches, preferences and push devices.
///
/// Failures keep their status code so callers can tell an older API without
/// these endpoints (404) from a network problem.
class NotificationsRemoteDataSource {
  final ApiClient _apiClient;

  NotificationsRemoteDataSource(this._apiClient);

  /// One page of the feed, newest first. Omit [before] for the first page.
  Future<ApiResult<FeedPage>> getFeed({
    String? before,
    String? beforeId,
    int limit = 20,
  }) async {
    final result = await _apiClient.get<Map<String, dynamic>>(
      ApiEndpoints.feed,
      queryParameters: {
        'limit': limit,
        if (before != null) 'before': before,
        if (beforeId != null) 'before_id': beforeId,
      },
    );
    if (result.isFailure) {
      return ApiResult.failure(result.error!, statusCode: result.statusCode);
    }

    try {
      return ApiResult.success(FeedPage.fromResponse(result.data!));
    } catch (e) {
      return ApiResult.failure('Failed to parse feed: $e');
    }
  }

  /// Unread news + notifications, for the Novinky badge.
  Future<ApiResult<int>> getUnreadCount() async {
    final result = await _apiClient.get<Map<String, dynamic>>(
      ApiEndpoints.notificationsUnreadCount,
    );
    return _unreadCountFrom(result);
  }

  /// Mark one notification read. Returns the new unread count.
  Future<ApiResult<int>> markRead(String notificationId) async {
    final result = await _apiClient.post<Map<String, dynamic>>(
      ApiEndpoints.notificationRead(notificationId),
    );
    return _unreadCountFrom(result);
  }

  /// Mark every notification and published article read. Returns the new
  /// unread count (0).
  Future<ApiResult<int>> markAllRead() async {
    final result = await _apiClient.post<Map<String, dynamic>>(
      ApiEndpoints.notificationsReadAll,
    );
    return _unreadCountFrom(result);
  }

  /// Send one batch of events (≤ 200). Null when it did not get through.
  Future<NotificationEventsAck?> sendEvents(
    List<NotificationEvent> events,
  ) async {
    final result = await _apiClient.post<Map<String, dynamic>>(
      ApiEndpoints.notificationEvents,
      data: {'events': [for (final e in events) e.toJson()]},
    );
    if (result.isFailure) {
      // 422 means the server will never take this batch; dropping it beats
      // retrying it forever. Anything else (offline, 5xx) is worth a retry.
      if (result.statusCode == 422) {
        return const NotificationEventsAck(accepted: 0);
      }
      return null;
    }

    final data = result.data?['data'];
    if (data is! Map) return NotificationEventsAck(accepted: events.length);
    return NotificationEventsAck(
      accepted: (data['accepted'] as num?)?.toInt() ?? events.length,
      unreadCount: (data['unread_count'] as num?)?.toInt(),
    );
  }

  Future<ApiResult<NotificationPreferences>> getPreferences() async {
    final result = await _apiClient.get<Map<String, dynamic>>(
      ApiEndpoints.notificationPreferences,
    );
    return _preferencesFrom(result);
  }

  /// Change any subset of the preferences. [changes] holds the API field
  /// names (`push_enabled`, `quiet_hours_start`, …); a null value is sent as
  /// null ("back to default" / "reminder off").
  Future<ApiResult<NotificationPreferences>> updatePreferences(
    Map<String, dynamic> changes,
  ) async {
    final result = await _apiClient.put<Map<String, dynamic>>(
      ApiEndpoints.notificationPreferences,
      data: changes,
    );
    return _preferencesFrom(result);
  }

  /// Tie this device's push token to the current session.
  Future<ApiResult<void>> registerPushDevice({
    required String token,
    required String platform,
    String? appVersion,
  }) async {
    final result = await _apiClient.post<dynamic>(
      ApiEndpoints.pushDevices,
      data: {
        'token': token,
        'platform': platform,
        if (appVersion != null && appVersion.isNotEmpty)
          'app_version': appVersion,
      },
    );
    if (result.isFailure) {
      return ApiResult.failure(result.error!, statusCode: result.statusCode);
    }
    return ApiResult.success(null, statusCode: result.statusCode);
  }

  /// Forget this device's push token. Idempotent on the server.
  Future<ApiResult<void>> unregisterPushDevice(String token) async {
    final result = await _apiClient.delete<dynamic>(
      ApiEndpoints.pushDevices,
      data: {'token': token},
    );
    if (result.isFailure) {
      return ApiResult.failure(result.error!, statusCode: result.statusCode);
    }
    return ApiResult.success(null, statusCode: result.statusCode);
  }

  // ── Parsing ─────────────────────────────────────────────────────────────

  ApiResult<int> _unreadCountFrom(ApiResult<Map<String, dynamic>> result) {
    if (result.isFailure) {
      return ApiResult.failure(result.error!, statusCode: result.statusCode);
    }
    final data = result.data?['data'];
    final count = data is Map ? data['unread_count'] : null;
    if (count is! num) {
      return ApiResult.failure('Missing unread_count',
          statusCode: result.statusCode);
    }
    return ApiResult.success(count.toInt(), statusCode: result.statusCode);
  }

  ApiResult<NotificationPreferences> _preferencesFrom(
    ApiResult<Map<String, dynamic>> result,
  ) {
    if (result.isFailure) {
      return ApiResult.failure(result.error!, statusCode: result.statusCode);
    }
    try {
      final data = result.data!['data'] as Map;
      return ApiResult.success(
        NotificationPreferences.fromJson(Map<String, dynamic>.from(data)),
        statusCode: result.statusCode,
      );
    } catch (e) {
      return ApiResult.failure('Failed to parse preferences: $e');
    }
  }
}
