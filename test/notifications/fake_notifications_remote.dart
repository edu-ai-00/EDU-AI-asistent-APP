import 'package:eduai/core/network/api_client.dart';
import 'package:eduai/core/notifications/notification_event_queue.dart';
import 'package:eduai/data/datasources/remote/notifications_remote_datasource.dart';
import 'package:eduai/models/feed_item.dart';
import 'package:eduai/models/notification_preferences.dart';

/// A feed row as the API sends it.
Map<String, dynamic> notificationRow(
  String id, {
  String title = 'Oznámení',
  String body = 'text',
  String? deepLink = '/dash',
  String category = 'pokrok',
  required DateTime createdAt,
  bool isRead = false,
}) =>
    {
      'kind': 'notification',
      'id': id,
      'notification_id': id,
      'type_key': 'course_completed',
      'category': category,
      'title': title,
      'body': body,
      'deep_link': deepLink,
      'created_at': createdAt.toUtc().toIso8601String(),
      'is_read': isRead,
    };

Map<String, dynamic> newsRow(
  int id, {
  String title = 'Novinka',
  String body = 'perex',
  required DateTime createdAt,
  bool isRead = false,
}) =>
    {
      'kind': 'news',
      'id': 'news-$id',
      'news_id': id,
      'title': title,
      'body': body,
      'deep_link': null,
      'created_at': createdAt.toUtc().toIso8601String(),
      'is_read': isRead,
    };

/// In-memory stand-in for the notification endpoints. Records every call;
/// [failWith] makes the next calls fail with that status (null = offline).
class FakeNotificationsRemote implements NotificationsRemoteDataSource {
  /// The whole feed, newest first. Pages are cut from it by the cursor.
  List<Map<String, dynamic>> feedRows = [];
  int pageUnreadCount = 0;

  bool offline = false;
  int? failStatus;

  int unreadCount = 0;
  int? unreadStatus; // e.g. 404 for an older API

  NotificationPreferences preferences = const NotificationPreferences(
    pushEnabled: true,
    timezone: 'Europe/Prague',
    mandatoryTypes: [
      MandatoryNotificationType(
        key: 'maintenance_notice',
        name: 'Plánovaná údržba nebo výpadek',
      ),
    ],
  );
  bool preferencesFail = false;

  final List<({String? before, String? beforeId, int limit})> feedCalls = [];
  final List<String> readCalls = [];
  int readAllCalls = 0;
  bool readAllFails = false;
  final List<List<NotificationEvent>> eventBatches = [];
  final List<Map<String, dynamic>> preferenceUpdates = [];
  final List<({String token, String platform, String? appVersion})>
      registeredDevices = [];
  final List<String> unregisteredTokens = [];

  ApiResult<T> _failure<T>() =>
      ApiResult.failure(offline ? 'No internet connection.' : 'error',
          statusCode: offline ? null : failStatus);

  bool get _failing => offline || failStatus != null;

  @override
  Future<ApiResult<FeedPage>> getFeed({
    String? before,
    String? beforeId,
    int limit = 20,
  }) async {
    feedCalls.add((before: before, beforeId: beforeId, limit: limit));
    if (_failing) return _failure();

    var start = 0;
    if (before != null) {
      final index = feedRows.indexWhere((row) => row['id'] == beforeId);
      start = index == -1 ? feedRows.length : index + 1;
    }
    final slice = feedRows.skip(start).take(limit).toList();
    final hasMore = start + slice.length < feedRows.length;
    final last = slice.isEmpty ? null : slice.last;
    return ApiResult.success(FeedPage.fromResponse({
      'data': slice,
      'meta': {
        'unread_count': pageUnreadCount,
        'next_before': hasMore ? last!['created_at'] : null,
        'next_before_id': hasMore ? last!['id'] : null,
        'has_more': hasMore,
      },
    }));
  }

  @override
  Future<ApiResult<int>> getUnreadCount() async {
    if (unreadStatus != null) {
      return ApiResult.failure('error', statusCode: unreadStatus);
    }
    if (_failing) return _failure();
    return ApiResult.success(unreadCount, statusCode: 200);
  }

  @override
  Future<ApiResult<int>> markRead(String notificationId) async {
    readCalls.add(notificationId);
    if (_failing) return _failure();
    unreadCount = unreadCount > 0 ? unreadCount - 1 : 0;
    return ApiResult.success(unreadCount);
  }

  @override
  Future<ApiResult<int>> markAllRead() async {
    readAllCalls++;
    if (readAllFails || _failing) return ApiResult.failure('error');
    unreadCount = 0;
    return ApiResult.success(0);
  }

  @override
  Future<NotificationEventsAck?> sendEvents(
    List<NotificationEvent> events,
  ) async {
    if (_failing) return null;
    eventBatches.add(List.of(events));
    return NotificationEventsAck(accepted: events.length, unreadCount: unreadCount);
  }

  @override
  Future<ApiResult<NotificationPreferences>> getPreferences() async {
    if (preferencesFail) return ApiResult.failure('error', statusCode: 500);
    if (_failing) return _failure();
    return ApiResult.success(preferences);
  }

  @override
  Future<ApiResult<NotificationPreferences>> updatePreferences(
    Map<String, dynamic> changes,
  ) async {
    preferenceUpdates.add(Map.of(changes));
    if (_failing) return _failure();
    var next = preferences;
    if (changes.containsKey('push_enabled')) {
      next = next.copyWith(pushEnabled: changes['push_enabled'] as bool);
    }
    if (changes.containsKey('quiet_hours_start')) {
      next = next.copyWith(
        quietHoursStart: () => changes['quiet_hours_start'] as String?,
        quietHoursEnd: () => changes['quiet_hours_end'] as String?,
      );
    }
    if (changes.containsKey('reminder_time')) {
      next = next.copyWith(reminderTime: () => changes['reminder_time'] as String?);
    }
    if (changes.containsKey('timezone')) {
      next = next.copyWith(timezone: () => changes['timezone'] as String?);
    }
    preferences = next;
    return ApiResult.success(next);
  }

  @override
  Future<ApiResult<void>> registerPushDevice({
    required String token,
    required String platform,
    String? appVersion,
  }) async {
    registeredDevices.add((token: token, platform: platform, appVersion: appVersion));
    if (_failing) return _failure();
    return ApiResult.success(null, statusCode: 201);
  }

  @override
  Future<ApiResult<void>> unregisterPushDevice(String token) async {
    unregisteredTokens.add(token);
    if (_failing) return _failure();
    return ApiResult.success(null);
  }
}
