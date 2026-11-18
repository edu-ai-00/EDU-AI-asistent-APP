// BR-DRPQMP: the "stay logged in permanently" box sat on the entry screen,
// under the course/login code, and on short screens it pushed the
// "Přihlášení/registrace" button below the fold. The client wants it on the
// e-mail/SSO form only. Without a visible choice the code flow has to start
// the default shared-device session (rule 5.6) — a tick left on the e-mail
// form must not carry over to it unseen.
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eduai/core/database/app_database.dart';
import 'package:eduai/core/providers/core_providers.dart';
import 'package:eduai/core/services/auth_token_storage.dart';
import 'package:eduai/core/services/guest_auth_service.dart';
import 'package:eduai/core/strings/app_strings.dart';
import 'package:eduai/core/sync/sync_service.dart';
import 'package:eduai/core/widgets/code_input_field.dart';
import 'package:eduai/data/repositories/course_repository.dart';
import 'package:eduai/pages/auth_page.dart';

/// Records the session mode the code was resolved with. Answers "not found"
/// so the test stops at the request itself.
class _RecordingGuestAuth extends Fake implements GuestAuthService {
  final List<bool> sharedDevice = [];

  @override
  Future<ResolveCodeResult?> resolveCode(
    String code, {
    bool sharedDevice = false,
    bool mergeGuest = false,
  }) async {
    this.sharedDevice.add(sharedDevice);
    return null;
  }
}

/// No bundled/local course matches, so the code goes to the API.
class _NoLocalCourses extends Fake implements CourseRepository {
  @override
  Future<Course?> findCourseByCode(String code) async => null;
}

/// Nothing left to flush before the login.
class _IdleSync extends Fake implements SyncService {
  @override
  Future<bool> hasPendingChanges() async => false;
}

final _keepLoggedInLabel = find.text(AppStrings.authKeepLoggedInLabel);

Future<({_RecordingGuestAuth guestAuth, SharedPreferences prefs})> _pump(
  WidgetTester tester, {
  bool startInLoginMode = false,
  Map<String, Object> storedPrefs = const {},
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  // The test-only Ahem font overflows some fixed-width buttons. Cosmetic.
  final oldOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exception.toString().contains('overflowed')) return;
    oldOnError?.call(details);
  };
  addTearDown(() => FlutterError.onError = oldOnError);

  SharedPreferences.setMockInitialValues(storedPrefs);
  final prefs = await SharedPreferences.getInstance();
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  final guestAuth = _RecordingGuestAuth();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        // Logged out: no token loaded.
        authTokenStorageProvider
            .overrideWithValue(AuthTokenStorage(prefs: prefs)),
        appDatabaseProvider.overrideWithValue(db),
        guestAuthServiceProvider.overrideWithValue(guestAuth),
        courseRepositoryProvider.overrideWithValue(_NoLocalCourses()),
        syncServiceProvider.overrideWithValue(_IdleSync()),
      ],
      child: MaterialApp(
        home: AuthPage(
          onEmailSubmit: (_) {},
          startInLoginMode: startInLoginMode,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 500));

  return (guestAuth: guestAuth, prefs: prefs);
}

Future<void> _enterCode(WidgetTester tester) async {
  await tester.enterText(
    find.descendant(
      of: find.byType(CodeInputField),
      matching: find.byType(TextField),
    ),
    'AB12CD',
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the entry screen has no "stay logged in" box', (tester) async {
    await _pump(tester);

    expect(find.byType(CodeInputField), findsOneWidget);
    expect(_keepLoggedInLabel, findsNothing);
    expect(find.byType(Checkbox), findsNothing);
  });

  testWidgets('the e-mail/SSO form still offers it, unticked by default',
      (tester) async {
    await _pump(tester);

    await tester.tap(find.text(AppStrings.authLoginSignUp));
    await tester.pumpAndSettle();

    expect(_keepLoggedInLabel, findsOneWidget);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
  });

  testWidgets('a code starts a shared-device session', (tester) async {
    final (:guestAuth, :prefs) = await _pump(tester);

    await _enterCode(tester);

    expect(guestAuth.sharedDevice, [isTrue]);
    expect(prefs.getBool('session_pending_shared_device'), isTrue);
  });

  testWidgets(
      'a box ticked on the e-mail form does not carry over to a code typed '
      'after going back', (tester) async {
    final (:guestAuth, :prefs) = await _pump(tester);

    await tester.tap(find.text(AppStrings.authLoginSignUp));
    await tester.pumpAndSettle();
    await tester.tap(_keepLoggedInLabel);
    await tester.pump();
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    await _enterCode(tester);

    expect(guestAuth.sharedDevice, [isTrue]);
    expect(prefs.getBool('session_pending_shared_device'), isTrue);
  });

  testWidgets(
      'a stored "stay logged in" choice does not reach the code flow',
      (tester) async {
    final (:guestAuth, prefs: _) = await _pump(
      tester,
      storedPrefs: {'session_pending_shared_device': false},
    );

    await _enterCode(tester);
    expect(guestAuth.sharedDevice, [isTrue]);
  });

  testWidgets('a stored "stay logged in" choice pre-ticks the e-mail form',
      (tester) async {
    await _pump(
      tester,
      startInLoginMode: true,
      storedPrefs: {'session_pending_shared_device': false},
    );

    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
  });
}
