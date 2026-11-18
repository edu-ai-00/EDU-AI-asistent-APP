import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../util/silent_log.dart';

/// The app-side states of a notification (NOTIF-8). The server derives
/// `created`/`queued`/`sent` itself; these four only the device can know.
enum NotificationEventType {
  delivered('delivered'),
  viewed('viewed'),
  clicked('clicked'),
  appOpened('app_opened');

  const NotificationEventType(this.wireName);

  /// Value of `event` in `POST /api/notifications/events`.
  final String wireName;

  static NotificationEventType? fromWire(Object? value) {
    for (final type in values) {
      if (type.wireName == value) return type;
    }
    return null;
  }
}

/// One entry of the events batch.
class NotificationEvent {
  final String notificationId;
  final NotificationEventType type;
  final DateTime occurredAt;

  const NotificationEvent({
    required this.notificationId,
    required this.type,
    required this.occurredAt,
  });

  /// Identity for deduplication: one event of each type per notification is
  /// all the server keeps (it records the first timestamp only).
  String get dedupKey => '$notificationId|${type.wireName}';

  Map<String, dynamic> toJson() => {
        'notification_id': notificationId,
        'event': type.wireName,
        'occurred_at': occurredAt.toUtc().toIso8601String(),
      };

  static NotificationEvent? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['notification_id'];
    final type = NotificationEventType.fromWire(raw['event']);
    final at = raw['occurred_at'] is String
        ? DateTime.tryParse(raw['occurred_at'] as String)
        : null;
    if (id is! String || id.isEmpty || type == null || at == null) return null;
    return NotificationEvent(notificationId: id, type: type, occurredAt: at);
  }
}

/// What the server answered to one batch.
class NotificationEventsAck {
  final int accepted;

  /// Unread count after the batch (`clicked`/`app_opened` mark rows read).
  final int? unreadCount;

  const NotificationEventsAck({required this.accepted, this.unreadCount});
}

/// Sends one batch. Returns null when the batch did not get through — the
/// events then stay queued for the next attempt.
typedef NotificationEventSender = Future<NotificationEventsAck?> Function(
  List<NotificationEvent> batch,
);

/// Outcome of [NotificationEventQueue.flush].
class NotificationEventsFlushResult {
  final int sent;
  final int? unreadCount;

  const NotificationEventsFlushResult({this.sent = 0, this.unreadCount});
}

/// Persistent outbox for notification events (`delivered`, `viewed`,
/// `clicked`, `app_opened`).
///
/// Events are recorded wherever they happen — a feed row scrolled into view,
/// a tap, a push opening the app — and flushed in batches later: on resume,
/// after the feed loads and after a sync. They survive an offline stretch and
/// an app restart (SharedPreferences), stop at [maxAge], and are wiped on
/// logout ([clear]) so nothing of one account is sent under the next.
class NotificationEventQueue {
  /// The outbox.
  static const String queueKey = 'notification_events_queue_v1';

  /// Events recorded by the background push isolate. A separate key because
  /// that isolate has its own SharedPreferences cache; it only ever appends,
  /// and this side only reads it (see [_mergeBackground]).
  static const String backgroundKey = 'notification_events_background_v1';

  /// Dedup keys of events already queued or sent, so re-rendering a row does
  /// not report it as viewed again.
  static const String recordedKey = 'notification_events_recorded_v1';

  /// Server limit per request.
  static const int maxBatch = 200;

  /// Older events are dropped rather than sent — the statistics they would
  /// feed have long been read.
  static const Duration maxAge = Duration(days: 30);

  /// Ceiling for the outbox and the dedup memory, so a device that stays
  /// offline for weeks cannot grow either without bound.
  static const int maxQueued = 2000;
  static const int maxRecorded = 2000;

  /// Ceiling for the background isolate's list.
  static const int maxBackground = 200;

  final SharedPreferences _prefs;
  final DateTime Function() _clock;

  NotificationEventQueue(this._prefs, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  Future<NotificationEventsFlushResult>? _flushing;

  /// Bumped by [clear] so a flush in flight does not write back the events of
  /// an account that has just logged out.
  int _generation = 0;

  /// Events waiting to be sent, oldest first.
  List<NotificationEvent> get pending => _read(queueKey);

  /// Queue [type] for [notificationId]. Returns false when the same event was
  /// already recorded (and therefore nothing was added).
  Future<bool> record(
    String notificationId,
    NotificationEventType type, {
    DateTime? at,
  }) async {
    if (notificationId.isEmpty) return false;
    final event = NotificationEvent(
      notificationId: notificationId,
      type: type,
      occurredAt: at ?? _clock(),
    );

    final recorded = _readRecorded();
    if (recorded.contains(event.dedupKey)) return false;

    final queue = pending..add(event);
    if (queue.length > maxQueued) {
      queue.removeRange(0, queue.length - maxQueued);
    }
    recorded.add(event.dedupKey);

    await _write(queue);
    await _writeRecorded(recorded);
    return true;
  }

  /// Send everything queued, [maxBatch] at a time.
  ///
  /// Does nothing without a session ([isAuthenticated] false): the server
  /// would 401, and a 401 logs the app out. A failed batch stops the flush
  /// and keeps its events for next time. Concurrent calls share one run.
  Future<NotificationEventsFlushResult> flush({
    required bool isAuthenticated,
    required NotificationEventSender send,
  }) {
    if (!isAuthenticated) {
      return Future.value(const NotificationEventsFlushResult());
    }
    return _flushing ??=
        _flush(send).whenComplete(() => _flushing = null);
  }

  Future<NotificationEventsFlushResult> _flush(
    NotificationEventSender send,
  ) async {
    final generation = _generation;
    await _mergeBackground();
    await _dropExpired();

    var sent = 0;
    int? unreadCount;
    while (true) {
      final queue = pending;
      if (queue.isEmpty) break;
      final batch = queue.take(maxBatch).toList();

      NotificationEventsAck? ack;
      try {
        ack = await send(batch);
      } catch (e, st) {
        silentLog('notification_events:flush', e, st);
      }
      if (ack == null) break;
      // Logged out while the request was in flight: the outbox is gone and
      // must stay gone.
      if (generation != _generation) break;

      sent += batch.length;
      unreadCount = ack.unreadCount ?? unreadCount;
      // By identity rather than position: events recorded meanwhile were
      // appended (and a full outbox trims its head). Keys are unique in the
      // outbox — [record] dedupes on them.
      final sentKeys = {for (final e in batch) e.dedupKey};
      final remaining = pending
        ..removeWhere((e) => sentKeys.contains(e.dedupKey));
      await _write(remaining);
    }
    return NotificationEventsFlushResult(sent: sent, unreadCount: unreadCount);
  }

  /// Wipe the outbox, the dedup memory and the background list. Logout.
  static Future<void> clear(SharedPreferences prefs) async {
    await prefs.remove(queueKey);
    await prefs.remove(backgroundKey);
    await prefs.remove(recordedKey);
  }

  /// [clear] for this instance, also cancelling the write-back of a flush in
  /// flight.
  Future<void> clearAll() async {
    _generation++;
    await clear(_prefs);
  }

  /// Record [type] from the background push isolate, which has no providers
  /// and its own SharedPreferences cache. Append-only and capped; the main
  /// isolate picks the list up on its next start (its own cache is loaded
  /// once per process) and dedupes it against [recordedKey].
  static Future<void> recordInBackground(
    SharedPreferences prefs,
    String notificationId,
    NotificationEventType type, {
    DateTime? at,
  }) async {
    if (notificationId.isEmpty) return;
    final list = _decode(prefs.getString(backgroundKey))
      ..add(NotificationEvent(
        notificationId: notificationId,
        type: type,
        occurredAt: at ?? DateTime.now(),
      ));
    if (list.length > maxBackground) {
      list.removeRange(0, list.length - maxBackground);
    }
    await prefs.setString(backgroundKey, _encode(list));
  }

  // ── Internals ───────────────────────────────────────────────────────────

  /// Move background-recorded events into the outbox. The background list is
  /// deliberately left in place: removing it here could delete what the
  /// other isolate appended after this process loaded its cache. Dedup makes
  /// re-reading it harmless.
  Future<void> _mergeBackground() async {
    final background = _read(backgroundKey);
    if (background.isEmpty) return;
    for (final event in background) {
      await record(event.notificationId, event.type, at: event.occurredAt);
    }
  }

  Future<void> _dropExpired() async {
    final cutoff = _clock().subtract(maxAge);
    final queue = pending;
    final kept = queue.where((e) => e.occurredAt.isAfter(cutoff)).toList();
    if (kept.length != queue.length) await _write(kept);
  }

  List<NotificationEvent> _read(String key) {
    try {
      return _decode(_prefs.getString(key));
    } catch (e, st) {
      silentLog('notification_events:read', e, st);
      return [];
    }
  }

  List<String> _readRecorded() =>
      List.of(_prefs.getStringList(recordedKey) ?? const <String>[]);

  Future<void> _write(List<NotificationEvent> events) async {
    if (events.isEmpty) {
      await _prefs.remove(queueKey);
    } else {
      await _prefs.setString(queueKey, _encode(events));
    }
  }

  Future<void> _writeRecorded(List<String> keys) async {
    if (keys.length > maxRecorded) {
      keys.removeRange(0, keys.length - maxRecorded);
    }
    await _prefs.setStringList(recordedKey, keys);
  }

  static List<NotificationEvent> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return [for (final row in list) ?NotificationEvent.tryParse(row)];
    } catch (_) {
      // A corrupt outbox is not worth recovering; start over.
      return [];
    }
  }

  static String _encode(List<NotificationEvent> events) =>
      jsonEncode([for (final e in events) e.toJson()]);
}
