// NOTIF-6 — Profile → "Oznámení" used to be a disabled "Připravujeme" row.
// It now opens the notification settings: the push switch for the optional
// types (with the mandatory ones listed), quiet hours with a reset, the
// learning reminder (off by default) and the device timezone sent along.
// Every change is saved straight away through the preferences endpoint.
//
//   flutter test test/widgets/notification_settings_page_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eduai/core/providers/core_providers.dart';
import 'package:eduai/core/providers/notification_providers.dart';
import 'package:eduai/core/strings/app_strings.dart';
import 'package:eduai/models/avatar_model.dart';
import 'package:eduai/models/notification_preferences.dart';
import 'package:eduai/pages/notification_settings_page.dart';
import 'package:eduai/pages/profile_page.dart';

import '../notifications/fake_notifications_remote.dart';

late FakeNotificationsRemote _remote;

Future<void> _pump(
  WidgetTester tester, {
  String deviceTimezone = 'Europe/Prague',
  NotificationPreferences? preferences,
}) async {
  tester.view.physicalSize = const Size(400, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  _remote = FakeNotificationsRemote();
  if (preferences != null) _remote.preferences = preferences;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        notificationsRemoteDataSourceProvider.overrideWithValue(_remote),
        notificationTimezoneSyncProvider.overrideWithValue(
          NotificationTimezoneSync(
            remote: _remote,
            prefs: prefs,
            isAuthenticated: () => true,
            resolve: () async => deviceTimezone,
          ),
        ),
      ],
      child: const MaterialApp(home: NotificationSettingsPage()),
    ),
  );
  await tester.pumpAndSettle();
}

Switch _switch(WidgetTester tester, Key key) =>
    tester.widget<Switch>(find.byKey(key));

void main() {
  testWidgets('renders the server preferences and the mandatory types',
      (tester) async {
    await _pump(tester);

    expect(find.text(AppStrings.profileNotifications), findsOneWidget);
    expect(_switch(tester, NotificationSettingsPage.pushSwitchKey).value, isTrue);
    expect(find.text('• Plánovaná údržba nebo výpadek'), findsOneWidget);
    // Quiet hours fall back to the server defaults.
    expect(find.text('20:00'), findsOneWidget);
    expect(find.text('07:00'), findsOneWidget);
    // Nothing to reset while on the defaults.
    final reset = tester.widget<TextButton>(
      find.byKey(NotificationSettingsPage.quietResetKey),
    );
    expect(reset.onPressed, isNull);
    // The reminder is off until a time is picked.
    expect(
      _switch(tester, NotificationSettingsPage.reminderSwitchKey).value,
      isFalse,
    );
    expect(find.byKey(NotificationSettingsPage.reminderTimeKey), findsNothing);
    expect(find.text(AppStrings.notifSettingsTimezone('Europe/Prague')),
        findsOneWidget);
    // Same timezone as the server: nothing to send.
    expect(_remote.preferenceUpdates, isEmpty);
  });

  testWidgets('the push switch saves push_enabled', (tester) async {
    await _pump(tester);

    await tester.tap(find.byKey(NotificationSettingsPage.pushSwitchKey));
    await tester.pumpAndSettle();

    expect(_remote.preferenceUpdates.single, {'push_enabled': false});
    expect(
      _switch(tester, NotificationSettingsPage.pushSwitchKey).value,
      isFalse,
    );
  });

  testWidgets('a failed save puts the switch back', (tester) async {
    await _pump(tester);
    _remote.failStatus = 500;

    await tester.tap(find.byKey(NotificationSettingsPage.pushSwitchKey));
    await tester.pumpAndSettle();

    expect(_switch(tester, NotificationSettingsPage.pushSwitchKey).value, isTrue);
    expect(find.text(AppStrings.notifSettingsSaveError), findsOneWidget);
  });

  testWidgets('quiet hours reset sends both bounds as null', (tester) async {
    await _pump(
      tester,
      preferences: const NotificationPreferences(
        pushEnabled: true,
        quietHoursStart: '21:30',
        quietHoursEnd: '06:00',
        timezone: 'Europe/Prague',
      ),
    );
    expect(find.text('21:30'), findsOneWidget);

    await tester.tap(find.byKey(NotificationSettingsPage.quietResetKey));
    await tester.pumpAndSettle();

    expect(_remote.preferenceUpdates.single,
        {'quiet_hours_start': null, 'quiet_hours_end': null});
    expect(find.text('20:00'), findsOneWidget);
    expect(find.text('07:00'), findsOneWidget);
  });

  testWidgets('switching the reminder on picks a time and saves it',
      (tester) async {
    await _pump(tester);

    await tester.tap(find.byKey(NotificationSettingsPage.reminderSwitchKey));
    await tester.pumpAndSettle();
    // The time picker opens on 17:00; accept it.
    final ok = find.text('OK');
    await tester.ensureVisible(ok);
    await tester.tap(ok);
    await tester.pumpAndSettle();

    expect(_remote.preferenceUpdates.single, {'reminder_time': '17:00'});
    expect(
      _switch(tester, NotificationSettingsPage.reminderSwitchKey).value,
      isTrue,
    );
    expect(find.byKey(NotificationSettingsPage.reminderTimeKey), findsOneWidget);
  });

  testWidgets('switching the reminder off sends null', (tester) async {
    await _pump(
      tester,
      preferences: const NotificationPreferences(
        pushEnabled: true,
        reminderTime: '18:15',
        timezone: 'Europe/Prague',
      ),
    );
    expect(find.text('18:15'), findsOneWidget);

    await tester.tap(find.byKey(NotificationSettingsPage.reminderSwitchKey));
    await tester.pumpAndSettle();

    expect(_remote.preferenceUpdates.single, {'reminder_time': null});
    expect(find.byKey(NotificationSettingsPage.reminderTimeKey), findsNothing);
  });

  testWidgets('a different device timezone is sent automatically',
      (tester) async {
    await _pump(tester, deviceTimezone: 'Europe/Bratislava');

    expect(_remote.preferenceUpdates.single, {'timezone': 'Europe/Bratislava'});
    expect(find.text(AppStrings.notifSettingsTimezone('Europe/Bratislava')),
        findsOneWidget);
  });

  testWidgets('an older API without the endpoint gets a notice, not a crash',
      (tester) async {
    tester.view.physicalSize = const Size(400, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final remote = FakeNotificationsRemote()..failStatus = 404;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          notificationsRemoteDataSourceProvider.overrideWithValue(remote),
        ],
        child: const MaterialApp(home: NotificationSettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.notifSettingsUnavailable), findsOneWidget);
  });

  testWidgets('Profile → Oznámení is a live row now', (tester) async {
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    var taps = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          avatarControllerProvider.overrideWith(_StubAvatarController.new),
        ],
        child: MaterialApp(
          home: ProfilePage(
            userName: 'Tester',
            userEmail: 'tester@example.com',
            onNotificationsTap: () => taps++,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text(AppStrings.profileComingSoon), findsNothing);
    await tester.tap(find.text(AppStrings.profileNotifications));
    await tester.pump();

    expect(taps, 1);
  });
}

class _StubAvatarController extends AvatarController {
  @override
  Future<AvatarState> build() async => AvatarState.empty;
}
