import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eduai/core/database/app_database.dart';
import 'package:eduai/core/sync/sync_service.dart';
import 'package:eduai/core/util/device_kind.dart';

/// The device stamped on work-time heartbeats, shown next to each session in
/// the admin "Čas práce" tab (BR-Y2TJ74).
void main() {
  group('DeviceKind.classify', () {
    test('a phone app is android/ios + mobile', () {
      expect(
        DeviceKind.classify(isWeb: false, os: TargetPlatform.android, shortestSide: 392),
        const DeviceKind(platform: 'android', type: 'mobile'),
      );
      expect(
        DeviceKind.classify(isWeb: false, os: TargetPlatform.iOS, shortestSide: 430),
        const DeviceKind(platform: 'ios', type: 'mobile'),
      );
    });

    test('a screen 600 dp or wider on its short side is a tablet', () {
      expect(
        DeviceKind.classify(isWeb: false, os: TargetPlatform.iOS, shortestSide: 820),
        const DeviceKind(platform: 'ios', type: 'tablet'),
      );
      expect(
        DeviceKind.classify(isWeb: false, os: TargetPlatform.android, shortestSide: 600),
        const DeviceKind(platform: 'android', type: 'tablet'),
      );
    });

    test('the browser reports web, typed by the OS it runs on', () {
      // Phone browser.
      expect(
        DeviceKind.classify(isWeb: true, os: TargetPlatform.android, shortestSide: 412),
        const DeviceKind(platform: 'web', type: 'mobile'),
      );
      // iPad Safari — the web engine maps the iPad's "Mac" user agent to iOS.
      expect(
        DeviceKind.classify(isWeb: true, os: TargetPlatform.iOS, shortestSide: 1024),
        const DeviceKind(platform: 'web', type: 'tablet'),
      );
      // A narrow browser window on a PC is still a PC.
      expect(
        DeviceKind.classify(isWeb: true, os: TargetPlatform.windows, shortestSide: 420),
        const DeviceKind(platform: 'web', type: 'desktop'),
      );
    });

    test('desktop apps are desktops', () {
      expect(
        DeviceKind.classify(isWeb: false, os: TargetPlatform.macOS, shortestSide: 900),
        const DeviceKind(platform: 'macos', type: 'desktop'),
      );
    });

    test('a phone OS with no known screen size has no type', () {
      expect(
        DeviceKind.classify(isWeb: false, os: TargetPlatform.android, shortestSide: 0),
        const DeviceKind(platform: 'android'),
      );
    });
  });

  group('SyncService.workHeartbeatsPayload', () {
    final row = WorkHeartbeatsTableData(
      clientUuid: '11111111-1111-4111-8111-111111111111',
      courseId: 'math',
      lessonId: 'l1',
      context: 'lesson',
      occurredAt: DateTime.utc(2026, 10, 16, 8),
      synced: false,
    );

    test('stamps the batch with the sending device', () {
      final payload = SyncService.workHeartbeatsPayload(
        [row],
        const DeviceKind(platform: 'ios', type: 'tablet'),
      );

      expect(payload['platform'], 'ios');
      expect(payload['device_type'], 'tablet');
      expect(payload['heartbeats'], [
        {
          'client_uuid': '11111111-1111-4111-8111-111111111111',
          'course_id': 'math',
          'lesson_id': 'l1',
          'occurred_at': '2026-10-16T08:00:00.000Z',
        },
      ]);
    });

    test('leaves device_type out when it is unknown', () {
      final payload = SyncService.workHeartbeatsPayload(
        [row],
        const DeviceKind(platform: 'android'),
      );

      expect(payload['platform'], 'android');
      expect(payload.containsKey('device_type'), isFalse);
    });
  });
}
