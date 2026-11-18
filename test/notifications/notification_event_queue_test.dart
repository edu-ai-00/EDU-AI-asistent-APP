// NOTIF-8 — the app-side states of a notification (delivered, viewed,
// clicked, app_opened) are queued on the device and sent in batches of at
// most 200 (`POST /api/notifications/events`, spec §5.1). The queue has to
// survive offline stretches and restarts, never send the same event twice,
// give up on events older than 30 days, and stay quiet without a session.
//
//   flutter test test/notifications/notification_event_queue_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eduai/core/notifications/notification_event_queue.dart';

void main() {
  late SharedPreferences prefs;
  late DateTime now;
  late NotificationEventQueue queue;
  late List<List<NotificationEvent>> sent;
  var online = true;

  Future<NotificationEventsAck?> send(List<NotificationEvent> batch) async {
    if (!online) return null;
    sent.add(batch);
    return NotificationEventsAck(accepted: batch.length, unreadCount: 2);
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    now = DateTime.utc(2026, 10, 7, 12);
    queue = NotificationEventQueue(prefs, clock: () => now);
    sent = [];
    online = true;
  });

  test('records an event with its time and wire name', () async {
    await queue.record('01JA', NotificationEventType.appOpened);

    final event = queue.pending.single;
    expect(event.notificationId, '01JA');
    expect(event.toJson(), {
      'notification_id': '01JA',
      'event': 'app_opened',
      'occurred_at': '2026-10-07T12:00:00.000Z',
    });
  });

  test('the same event for the same notification is recorded once', () async {
    expect(await queue.record('01JA', NotificationEventType.viewed), isTrue);
    expect(await queue.record('01JA', NotificationEventType.viewed), isFalse);
    expect(await queue.record('01JA', NotificationEventType.clicked), isTrue);
    expect(await queue.record('01JB', NotificationEventType.viewed), isTrue);

    expect(queue.pending, hasLength(3));
  });

  test('…and not again after it was sent (a re-rendered row)', () async {
    await queue.record('01JA', NotificationEventType.viewed);
    await queue.flush(isAuthenticated: true, send: send);

    expect(await queue.record('01JA', NotificationEventType.viewed), isFalse);
    expect(queue.pending, isEmpty);
  });

  test('flushes in batches of at most 200, oldest first', () async {
    for (var i = 0; i < 450; i++) {
      await queue.record('01J$i', NotificationEventType.delivered);
    }

    final result = await queue.flush(isAuthenticated: true, send: send);

    expect(sent.map((b) => b.length), [200, 200, 50]);
    expect(sent.first.first.notificationId, '01J0');
    expect(result.sent, 450);
    expect(result.unreadCount, 2);
    expect(queue.pending, isEmpty);
  });

  test('a failed batch stays queued for the next flush', () async {
    await queue.record('01JA', NotificationEventType.clicked);
    online = false;

    final result = await queue.flush(isAuthenticated: true, send: send);

    expect(result.sent, 0);
    expect(queue.pending, hasLength(1));

    online = true;
    await queue.flush(isAuthenticated: true, send: send);
    expect(sent.single.single.notificationId, '01JA');
    expect(queue.pending, isEmpty);
  });

  test('a sender that throws is a failed batch, not a crash', () async {
    await queue.record('01JA', NotificationEventType.clicked);

    final result = await queue.flush(
      isAuthenticated: true,
      send: (_) async => throw Exception('boom'),
    );

    expect(result.sent, 0);
    expect(queue.pending, hasLength(1));
  });

  test('nothing is sent without a session', () async {
    await queue.record('01JA', NotificationEventType.viewed);

    await queue.flush(isAuthenticated: false, send: send);

    expect(sent, isEmpty);
    expect(queue.pending, hasLength(1));
  });

  test('survives an app restart', () async {
    await queue.record('01JA', NotificationEventType.viewed);

    final restarted = NotificationEventQueue(prefs, clock: () => now);
    expect(restarted.pending.single.notificationId, '01JA');
    // The dedup memory survives too.
    expect(await restarted.record('01JA', NotificationEventType.viewed), isFalse);
  });

  test('events older than 30 days are dropped, not sent', () async {
    await queue.record(
      '01JOLD',
      NotificationEventType.viewed,
      at: now.subtract(const Duration(days: 31)),
    );
    await queue.record(
      '01JNEW',
      NotificationEventType.viewed,
      at: now.subtract(const Duration(days: 29)),
    );

    await queue.flush(isAuthenticated: true, send: send);

    expect(sent.single.map((e) => e.notificationId), ['01JNEW']);
    expect(queue.pending, isEmpty);
  });

  test('concurrent flushes share one run', () async {
    await queue.record('01JA', NotificationEventType.viewed);

    await Future.wait([
      queue.flush(isAuthenticated: true, send: send),
      queue.flush(isAuthenticated: true, send: send),
    ]);

    expect(sent, hasLength(1));
  });

  test('logout clears the outbox and a flush in flight does not restore it',
      () async {
    await queue.record('01JA', NotificationEventType.viewed);
    await queue.record('01JB', NotificationEventType.viewed);

    final flushing = queue.flush(
      isAuthenticated: true,
      send: (batch) async {
        await queue.clearAll(); // logout while the request is out
        return NotificationEventsAck(accepted: batch.length);
      },
    );
    await flushing;

    expect(queue.pending, isEmpty);
    expect(prefs.containsKey(NotificationEventQueue.queueKey), isFalse);
    expect(prefs.containsKey(NotificationEventQueue.recordedKey), isFalse);
  });

  test('events from the background isolate are picked up and deduped',
      () async {
    await NotificationEventQueue.recordInBackground(
      prefs,
      '01JBG',
      NotificationEventType.delivered,
      at: now,
    );

    await queue.flush(isAuthenticated: true, send: send);
    expect(sent.single.single.notificationId, '01JBG');

    // Still in the background list (only that isolate writes it), but never
    // sent twice.
    await queue.flush(isAuthenticated: true, send: send);
    expect(sent, hasLength(1));
  });

  test('a corrupt outbox starts over instead of throwing', () async {
    await prefs.setString(NotificationEventQueue.queueKey, '{not json');

    expect(queue.pending, isEmpty);
    expect(await queue.record('01JA', NotificationEventType.viewed), isTrue);
  });
}
