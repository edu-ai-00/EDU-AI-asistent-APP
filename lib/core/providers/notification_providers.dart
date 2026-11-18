import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/datasources/remote/notifications_remote_datasource.dart';
import '../../data/repositories/feed_repository.dart';
import '../../models/feed_item.dart';
import '../../routing/deep_link.dart';
import '../notifications/notification_event_queue.dart';
import '../notifications/push/firebase_push_messaging.dart';
import '../notifications/push/push_config.dart';
import '../notifications/push/push_controller.dart';
import '../notifications/push/push_messaging.dart';
import '../util/silent_log.dart';
import 'core_providers.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Notifications (NOTIF-3/4/6) — the Novinky feed, its events, push and
// preferences. Contract: docs/superpowers/specs/2026-10-07-notification-system-design.md
// ═══════════════════════════════════════════════════════════════════════════

final notificationsRemoteDataSourceProvider =
    Provider<NotificationsRemoteDataSource>((ref) {
  return NotificationsRemoteDataSource(ref.watch(apiClientProvider));
});

final feedRepositoryProvider = Provider<FeedRepository>((ref) {
  return FeedRepository(
    ref.watch(notificationsRemoteDataSourceProvider),
    ref.watch(newsRepositoryProvider),
    ref.watch(sharedPreferencesProvider),
    isAuthenticated: () => ref.read(apiClientProvider).isAuthenticated,
  );
});

final notificationEventQueueProvider = Provider<NotificationEventQueue>((ref) {
  return NotificationEventQueue(ref.watch(sharedPreferencesProvider));
});

/// Records notification events and sends them, keeping the Novinky badge in
/// step with the unread count the server answers with.
class NotificationEvents {
  NotificationEvents(this._ref);

  final Ref _ref;

  NotificationEventQueue get _queue => _ref.read(notificationEventQueueProvider);

  /// Queue [type] for [notificationId] (nothing for a null id — news rows
  /// have none). Never throws.
  Future<void> record(String? notificationId, NotificationEventType type) async {
    if (notificationId == null || notificationId.isEmpty) return;
    try {
      await _queue.record(notificationId, type);
    } catch (e, st) {
      silentLog('notification_events:record', e, st);
    }
  }

  /// Send what is queued. Skipped without a session. Never throws.
  Future<void> flush() async {
    try {
      final remote = _ref.read(notificationsRemoteDataSourceProvider);
      final result = await _queue.flush(
        isAuthenticated: _ref.read(apiClientProvider).isAuthenticated,
        send: remote.sendEvents,
      );
      final unread = result.unreadCount;
      if (unread != null) {
        _ref.read(unreadNewsCountProvider.notifier).set(unread);
      }
    } catch (e, st) {
      silentLog('notification_events:flush', e, st);
    }
  }
}

final notificationEventsProvider = Provider<NotificationEvents>((ref) {
  return NotificationEvents(ref);
});

// ── Feed ─────────────────────────────────────────────────────────────────

/// What Novinky renders.
class FeedState {
  final List<FeedItem> items;
  final int unreadCount;
  final bool hasMore;
  final String? nextBefore;
  final String? nextBeforeId;

  /// Showing the copy kept for offline.
  final bool fromCache;

  /// The server predates the notification feed; this is the old news list.
  final bool legacy;

  final bool loadingMore;
  final bool loadMoreFailed;

  const FeedState({
    required this.items,
    required this.unreadCount,
    this.hasMore = false,
    this.nextBefore,
    this.nextBeforeId,
    this.fromCache = false,
    this.legacy = false,
    this.loadingMore = false,
    this.loadMoreFailed = false,
  });

  factory FeedState.fromResult(FeedFetchResult result) => FeedState(
        items: result.page.items,
        unreadCount: result.page.unreadCount,
        hasMore: result.page.hasMore,
        nextBefore: result.page.nextBefore,
        nextBeforeId: result.page.nextBeforeId,
        fromCache: result.fromCache,
        legacy: result.legacy,
      );

  bool get hasUnread => items.any((item) => !item.isRead);

  FeedState copyWith({
    List<FeedItem>? items,
    int? unreadCount,
    bool? hasMore,
    String? Function()? nextBefore,
    String? Function()? nextBeforeId,
    bool? loadingMore,
    bool? loadMoreFailed,
  }) {
    return FeedState(
      items: items ?? this.items,
      unreadCount: unreadCount ?? this.unreadCount,
      hasMore: hasMore ?? this.hasMore,
      nextBefore: nextBefore != null ? nextBefore() : this.nextBefore,
      nextBeforeId: nextBeforeId != null ? nextBeforeId() : this.nextBeforeId,
      fromCache: fromCache,
      legacy: legacy,
      loadingMore: loadingMore ?? this.loadingMore,
      loadMoreFailed: loadMoreFailed ?? this.loadMoreFailed,
    );
  }
}

/// The Novinky feed: first page, infinite scroll, read state.
///
/// Auto-disposed with the page, like the news list before it — opening the
/// tab fetches afresh, and nothing polls a feed nobody is looking at.
class FeedController extends AutoDisposeAsyncNotifier<FeedState> {
  /// Bumped by every reload, so a page that was in flight across one is
  /// dropped instead of being appended to the wrong list.
  int _generation = 0;

  FeedRepository get _repository => ref.read(feedRepositoryProvider);

  @override
  Future<FeedState> build() async {
    _generation++;
    // Disposed (the page closed) or rebuilt: whatever is still in flight must
    // not write into the state any more.
    ref.onDispose(() => _generation++);
    final result = await ref.watch(feedRepositoryProvider).fetchFirstPage();
    _afterLoad(result.page.unreadCount);
    return FeedState.fromResult(result);
  }

  /// Pull-to-refresh: back to the newest page. A failure keeps what is shown.
  Future<void> refresh() async {
    final previous = state.valueOrNull;
    final generation = ++_generation;
    try {
      final result = await _repository.fetchFirstPage();
      if (generation != _generation) return;
      state = AsyncData(FeedState.fromResult(result));
      _afterLoad(result.page.unreadCount);
    } catch (e, st) {
      silentLog('feed:refresh', e, st);
      if (generation != _generation) return;
      if (previous == null) state = AsyncError(e, st);
    }
  }

  /// Bring in what is new at the top without throwing away the pages already
  /// scrolled through — the foreground poll and incoming pushes use this.
  Future<void> refreshHead() async {
    final previous = state.valueOrNull;
    if (previous == null) {
      if (state.hasError) await refresh();
      return;
    }
    final generation = _generation;
    try {
      final result = await _repository.fetchFirstPage();
      if (generation != _generation) return;
      final current = state.valueOrNull ?? previous;
      state = AsyncData(_mergeHead(current, result));
      _afterLoad(result.page.unreadCount);
    } catch (e, st) {
      silentLog('feed:refresh-head', e, st);
    }
  }

  /// The next page, when there is one.
  Future<void> loadMore() async {
    final current = state.valueOrNull;
    final before = current?.nextBefore;
    if (current == null ||
        before == null ||
        !current.hasMore ||
        current.loadingMore) {
      return;
    }
    final generation = _generation;
    state = AsyncData(current.copyWith(loadingMore: true, loadMoreFailed: false));
    try {
      final page = await _repository.fetchNextPage(
        before: before,
        beforeId: current.nextBeforeId,
      );
      if (generation != _generation) return;
      final latest = state.valueOrNull ?? current;
      final known = {for (final item in latest.items) item.id};
      state = AsyncData(latest.copyWith(
        items: [
          ...latest.items,
          for (final item in page.items)
            if (!known.contains(item.id)) item,
        ],
        unreadCount: page.unreadCount,
        hasMore: page.hasMore,
        nextBefore: () => page.nextBefore,
        nextBeforeId: () => page.nextBeforeId,
        loadingMore: false,
      ));
      _setBadge(page.unreadCount);
    } catch (e, st) {
      silentLog('feed:load-more', e, st);
      if (generation != _generation) return;
      final latest = state.valueOrNull ?? current;
      state = AsyncData(
        latest.copyWith(loadingMore: false, loadMoreFailed: true),
      );
    }
  }

  /// "Označit vše jako přečtené". Optimistic; on failure the dots come back
  /// and false is returned so the page can say so.
  Future<bool> markAllRead() async {
    final current = state.valueOrNull;
    if (current == null) return false;
    final generation = _generation;
    final repository = _repository;
    final wereUnread = {
      for (final item in current.items)
        if (!item.isRead) item.id,
    };
    state = AsyncData(current.copyWith(
      items: [for (final item in current.items) item.copyWith(isRead: true)],
      unreadCount: 0,
    ));
    _setBadge(0);

    try {
      final count = await repository.markAllRead();
      if (generation == _generation) _setBadge(count);
      return true;
    } catch (e, st) {
      silentLog('feed:mark-all-read', e, st);
      if (generation != _generation) return false;
      final latest = state.valueOrNull ?? current;
      state = AsyncData(latest.copyWith(
        items: [
          for (final item in latest.items)
            wereUnread.contains(item.id) ? item.copyWith(isRead: false) : item,
        ],
        unreadCount: current.unreadCount,
      ));
      _setBadge(current.unreadCount);
      return false;
    }
  }

  /// A notification row was tapped: record `clicked`, show it read straight
  /// away and tell the server. Opening the link is the caller's job.
  Future<void> openNotification(FeedItem item) async {
    final id = item.notificationId;
    if (id == null) return;
    final generation = _generation;
    final events = ref.read(notificationEventsProvider);
    final repository = _repository;
    await events.record(id, NotificationEventType.clicked);

    if (!item.isRead) {
      if (generation == _generation) {
        markReadLocally((i) => i.notificationId == id);
      } else {
        repository.updateCachedReadState((i) => i.notificationId == id);
      }
      unawaited(repository.markRead(id).then(_setBadge).catchError((Object e) {
        // The queued `clicked` marks it read server-side once it gets through.
        silentLog('feed:mark-read', e);
      }));
    }
    unawaited(events.flush());
  }

  /// A row came into view for the first time: `viewed` (notifications only —
  /// news has no notification id).
  void recordViewed(FeedItem item) {
    if (!item.isNotification) return;
    unawaited(ref
        .read(notificationEventsProvider)
        .record(item.notificationId, NotificationEventType.viewed));
  }

  /// Show every item matching [test] as read, here, in the badge and in the
  /// offline copy. No request.
  void markReadLocally(bool Function(FeedItem item) test) {
    _repository.updateCachedReadState(test);
    final current = state.valueOrNull;
    if (current == null) return;
    final changed = current.items.where((i) => !i.isRead && test(i)).length;
    if (changed == 0) return;
    final unread = math.max(0, current.unreadCount - changed);
    state = AsyncData(current.copyWith(
      items: [
        for (final item in current.items)
          if (!item.isRead && test(item)) item.copyWith(isRead: true) else item,
      ],
      unreadCount: unread,
    ));
    final badge = ref.read(unreadNewsCountProvider);
    _setBadge(math.max(0, badge - changed));
  }

  FeedState _mergeHead(FeedState current, FeedFetchResult result) {
    final fresh = FeedState.fromResult(result);
    // Nothing beyond the first page was loaded (or there is nothing beyond
    // it), or the fresh copy is only the offline one: take it as it is.
    if (!result.page.hasMore ||
        result.fromCache ||
        current.items.length <= result.page.items.length) {
      return fresh;
    }
    final ids = {for (final item in result.page.items) item.id};
    final oldest = result.page.items.isEmpty
        ? null
        : result.page.items.last.createdAt;
    final tail = [
      for (final item in current.items)
        if (!ids.contains(item.id) &&
            (oldest == null || !item.createdAt.isAfter(oldest)))
          item,
    ];
    return current.copyWith(
      items: [...result.page.items, ...tail],
      unreadCount: result.page.unreadCount,
    );
  }

  void _afterLoad(int unreadCount) {
    // After this build/update completes — mutating another provider while
    // this one builds is not allowed.
    Future.microtask(() {
      _setBadge(unreadCount);
      try {
        unawaited(ref.read(notificationEventsProvider).flush());
      } catch (e, st) {
        // Disposed in between (the page closed): nothing to flush for.
        silentLog('feed:after-load', e, st);
      }
    });
  }

  void _setBadge(int count) {
    try {
      ref.read(unreadNewsCountProvider.notifier).set(count);
    } catch (e, st) {
      silentLog('feed:badge', e, st);
    }
  }
}

final feedControllerProvider =
    AsyncNotifierProvider.autoDispose<FeedController, FeedState>(
  FeedController.new,
);

/// Mark feed items read locally from outside the feed page (an article
/// opened and marked read on its own page). Updates the live feed when it is
/// on screen, the offline copy either way.
void markFeedItemsReadLocally(
  WidgetRef ref,
  bool Function(FeedItem item) test,
) {
  try {
    if (ref.exists(feedControllerProvider)) {
      ref.read(feedControllerProvider.notifier).markReadLocally(test);
    } else {
      ref.read(feedRepositoryProvider).updateCachedReadState(test);
    }
  } catch (e, st) {
    silentLog('feed:mark-read-locally', e, st);
  }
}

// ── Push ─────────────────────────────────────────────────────────────────

/// The messaging SDK, or null where push is not offered (web, desktop, a
/// build without the Firebase dart-defines).
final pushMessagingProvider = Provider<PushMessaging?>((ref) {
  return createPushMessaging();
});

/// The app version sent with the push token (`app_version`). A provider so
/// tests can answer without the platform channel.
final pushAppVersionProvider = Provider<Future<String?> Function()>((ref) {
  return _appVersion;
});

final pushControllerProvider = Provider<PushController>((ref) {
  final controller = PushController(
    messaging: ref.watch(pushMessagingProvider),
    platform: pushPlatformName(),
    remote: ref.watch(notificationsRemoteDataSourceProvider),
    prefs: ref.watch(sharedPreferencesProvider),
    isAuthenticated: () => ref.read(apiClientProvider).isAuthenticated,
    appVersion: ref.watch(pushAppVersionProvider),
    onForeground: (message) => _onForegroundPush(ref, message),
    onOpened: (message) => _onOpenedPush(ref, message),
  );
  ref.onDispose(controller.dispose);
  return controller;
});

Future<String?>? _appVersionFuture;

Future<String?> _appVersion() => _appVersionFuture ??= () async {
      try {
        return (await PackageInfo.fromPlatform()).version;
      } catch (e, st) {
        silentLog('push:app-version', e, st);
        return null;
      }
    }();

/// A push arrived while the app is open: count it delivered and bring the
/// badge and a visible feed up to date. The banner is `MainScreen`'s.
Future<void> _onForegroundPush(Ref ref, PushMessage message) async {
  final events = ref.read(notificationEventsProvider);
  await events.record(message.notificationId, NotificationEventType.delivered);
  unawaited(events.flush());
  unawaited(ref.read(unreadNewsCountProvider.notifier).refresh());
  if (ref.exists(feedControllerProvider)) {
    unawaited(ref.read(feedControllerProvider.notifier).refreshHead());
  }
}

/// A push was tapped: it opened the app and was clicked. Its link waits in
/// [pendingNotificationLinkProvider] until `MainScreen` can open it.
Future<void> _onOpenedPush(Ref ref, PushMessage message) async {
  final events = ref.read(notificationEventsProvider);
  await events.record(message.notificationId, NotificationEventType.appOpened);
  await events.record(message.notificationId, NotificationEventType.clicked);
  ref.read(pendingNotificationLinkProvider.notifier).state =
      message.deepLink ?? '/dash';
  unawaited(events.flush());
}

/// Whether Novinky shows the "Chceš dostávat upozornění?" card.
final pushPrimingVisibleProvider = FutureProvider.autoDispose<bool>((ref) {
  return ref.watch(pushControllerProvider).shouldOfferPriming();
});

// ── Preferences ──────────────────────────────────────────────────────────

/// Sends the device's IANA timezone with the notification preferences, so
/// quiet hours and the learning reminder follow the user's clock.
class NotificationTimezoneSync {
  /// The timezone last accepted by the server, so it is sent once, not on
  /// every start. Cleared on logout.
  static const String sentKey = 'notification_timezone_sent_v1';

  final NotificationsRemoteDataSource _remote;
  final SharedPreferences _prefs;
  final bool Function() _isAuthenticated;
  final Future<String?> Function() _resolve;

  NotificationTimezoneSync({
    required NotificationsRemoteDataSource remote,
    required SharedPreferences prefs,
    required bool Function() isAuthenticated,
    Future<String?> Function()? resolve,
  })  : _remote = remote,
        _prefs = prefs,
        _isAuthenticated = isAuthenticated,
        _resolve = resolve ?? _deviceTimezone;

  /// The device's IANA timezone, or null when the platform cannot say.
  Future<String?> deviceTimezone() async {
    try {
      final tz = await _resolve();
      return (tz == null || tz.trim().isEmpty) ? null : tz.trim();
    } catch (e, st) {
      silentLog('notification_tz:resolve', e, st);
      return null;
    }
  }

  /// Send the device timezone when it differs from the last one sent.
  /// Unresolvable → nothing is sent (the server keeps its default).
  Future<void> sync() async {
    if (!_isAuthenticated()) return;
    final tz = await deviceTimezone();
    if (tz == null || _prefs.getString(sentKey) == tz) return;
    try {
      final result = await _remote.updatePreferences({'timezone': tz});
      if (result.isSuccess) await _prefs.setString(sentKey, tz);
    } catch (e, st) {
      silentLog('notification_tz:sync', e, st);
    }
  }

  /// Record that [tz] reached the server by another route (the settings page).
  Future<void> markSent(String tz) => _prefs.setString(sentKey, tz);

  static Future<void> clear(SharedPreferences prefs) => prefs.remove(sentKey);

  static Future<String?> _deviceTimezone() async =>
      (await FlutterTimezone.getLocalTimezone()).identifier;
}

final notificationTimezoneSyncProvider =
    Provider<NotificationTimezoneSync>((ref) {
  return NotificationTimezoneSync(
    remote: ref.watch(notificationsRemoteDataSourceProvider),
    prefs: ref.watch(sharedPreferencesProvider),
    isAuthenticated: () => ref.read(apiClientProvider).isAuthenticated,
  );
});

// ── Logout ───────────────────────────────────────────────────────────────

/// Everything the notification layer keeps on the device for one account:
/// the feed copy, the event outbox, the priming answer, the registered
/// token, the last timezone sent, a push link not yet opened, the badge.
/// Called from the logout teardown so none of it reaches the next person on
/// a shared device.
Future<void> clearNotificationLocalState(Ref ref) async {
  final prefs = ref.read(sharedPreferencesProvider);
  // Through the instance, so a flush in flight cannot write the outbox back.
  await ref.read(notificationEventQueueProvider).clearAll();
  await FeedRepository.clearCache(prefs);
  await PushController.clearLocalState(prefs);
  await NotificationTimezoneSync.clear(prefs);
  ref.read(pendingNotificationLinkProvider.notifier).state = null;
  ref.read(unreadNewsCountProvider.notifier).set(0);
}
