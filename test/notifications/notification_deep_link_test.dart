// NOTIF-4 D — a notification's deep link is resolved by the app itself, and
// anything it does not know (or cannot open) must land on the dashboard:
// never an error page, never a blank screen (spec §8).
//
//   flutter test test/notifications/notification_deep_link_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eduai/core/providers/core_providers.dart';
import 'package:eduai/core/providers/navigation_providers.dart';
import 'package:eduai/core/providers/notification_providers.dart';
import 'package:eduai/pages/notification_settings_page.dart';
import 'package:eduai/routing/notification_deep_link.dart';

import 'fake_notifications_remote.dart';

const _tab = NotificationLinkTarget.tab;
const _of = NotificationLinkTarget.of;

void main() {
  group('resolveNotificationLink', () {
    test('main tabs', () {
      expect(resolveNotificationLink('/dash'), _tab(0));
      expect(resolveNotificationLink('/chat'), _tab(1));
      expect(resolveNotificationLink('/library'), _tab(2));
      expect(resolveNotificationLink('/courses'), _tab(3));
      expect(resolveNotificationLink('/news'), _tab(4));
      expect(resolveNotificationLink('/'), _tab(0));
    });

    test('a course by code, including the /pin alias', () {
      expect(
        resolveNotificationLink('/course/ABC123'),
        const NotificationLinkTarget.course('ABC123'),
      );
      expect(
        resolveNotificationLink('/pin/676767'),
        const NotificationLinkTarget.course('676767'),
      );
    });

    test('pushed pages', () {
      expect(resolveNotificationLink('/practice'),
          _of(NotificationLinkKind.practice));
      expect(resolveNotificationLink('/quiz'), _of(NotificationLinkKind.quiz));
      expect(resolveNotificationLink('/games'), _of(NotificationLinkKind.games));
      expect(resolveNotificationLink('/tools'), _of(NotificationLinkKind.games));
      expect(
          resolveNotificationLink('/profile'), _of(NotificationLinkKind.profile));
      expect(
        resolveNotificationLink('/settings/notifications'),
        _of(NotificationLinkKind.notificationSettings),
      );
    });

    test('tolerates a trailing slash, a query and upper case', () {
      expect(resolveNotificationLink('/news/'), _tab(4));
      expect(resolveNotificationLink('/quiz?from=push'),
          _of(NotificationLinkKind.quiz));
      expect(resolveNotificationLink(' /Practice '),
          _of(NotificationLinkKind.practice));
      // The code itself keeps its case.
      expect(resolveNotificationLink('/COURSE/AbC'),
          const NotificationLinkTarget.course('AbC'));
    });

    test('absolute links on the app host resolve like relative ones', () {
      expect(resolveNotificationLink('https://app.edu-ai.eu/courses'), _tab(3));
      expect(
        resolveNotificationLink('https://app.edu-ai.eu/course/XYZ'),
        const NotificationLinkTarget.course('XYZ'),
      );
    });

    test('everything else falls back to the dashboard', () {
      for (final link in [
        null,
        '',
        '   ',
        '/unknown',
        '/course',
        '/course/',
        '/course/ABC/extra',
        '/settings',
        '/settings/privacy',
        '/news/12',
        'https://evil.example.com/dash',
        'mailto:someone@example.com',
        'javascript:alert(1)',
        '::not a uri::',
        '/{{course_code}}',
      ]) {
        expect(
          resolveNotificationLink(link),
          NotificationLinkTarget.dashboard,
          reason: 'link: $link',
        );
      }
    });
  });

  group('openNotificationLink', () {
    late WidgetRef capturedRef;
    late BuildContext capturedContext;
    late FakeNotificationsRemote remote;

    Future<void> pump(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      remote = FakeNotificationsRemote();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            notificationsRemoteDataSourceProvider.overrideWithValue(remote),
            notificationTimezoneSyncProvider.overrideWithValue(
              NotificationTimezoneSync(
                remote: remote,
                prefs: prefs,
                isAuthenticated: () => true,
                resolve: () async => 'Europe/Prague',
              ),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  capturedRef = ref;
                  capturedContext = context;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('a tab link switches the tab', (tester) async {
      await pump(tester);

      await openNotificationLink(capturedContext, capturedRef, '/courses');
      expect(capturedRef.read(mainTabIndexProvider), 3);

      await openNotificationLink(capturedContext, capturedRef, '/news');
      expect(capturedRef.read(mainTabIndexProvider), 4);
    });

    testWidgets('an unknown link lands on the dashboard', (tester) async {
      await pump(tester);
      capturedRef.read(mainTabIndexProvider.notifier).state = 4;

      await openNotificationLink(capturedContext, capturedRef, '/nonsense');

      expect(capturedRef.read(mainTabIndexProvider), 0);
    });

    testWidgets('profile and games go through the shell intent',
        (tester) async {
      await pump(tester);

      await openNotificationLink(capturedContext, capturedRef, '/profile');
      expect(capturedRef.read(pendingShellIntentProvider),
          ShellIntent.openProfile);

      capturedRef.read(pendingShellIntentProvider.notifier).state = null;
      await openNotificationLink(capturedContext, capturedRef, '/games');
      expect(capturedRef.read(pendingShellIntentProvider),
          ShellIntent.openDoplnky);
    });

    testWidgets('a course code that does not resolve falls back too',
        (tester) async {
      await pump(tester);
      capturedRef.read(mainTabIndexProvider.notifier).state = 4;

      // Too short to be a join code: fails before any network call.
      await openNotificationLink(capturedContext, capturedRef, '/course/12');
      await tester.pump();

      expect(capturedRef.read(mainTabIndexProvider), 0);
    });

    testWidgets('/settings/notifications opens the settings page',
        (tester) async {
      tester.view.physicalSize = const Size(400, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await pump(tester);

      await openNotificationLink(
        capturedContext,
        capturedRef,
        '/settings/notifications',
      );
      await tester.pumpAndSettle();

      expect(find.byType(NotificationSettingsPage), findsOneWidget);
    });
  });
}
