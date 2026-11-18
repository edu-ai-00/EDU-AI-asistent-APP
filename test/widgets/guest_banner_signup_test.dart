// One way to sign up, whatever the screen size (BR-UMRKQ9).
//
// On a wide window a guest signs up from the sidebar's "Registrovat se" card,
// which pushes the login screen (MainScreen's guest-upgrade AuthPage) — back
// from there returns to the app. A phone has no sidebar, so the same guest gets
// the e-mail banner instead, and tapping it used to open a separate
// "Registrace" dialog with its own e-mail form. Two registrations, depending
// on the device. The banner now hands a guest to the same route the card
// opens; only a registered user whose e-mail is still unverified keeps the
// verification dialog, which is the same on every layout.
//
//   flutter test test/widgets/guest_banner_signup_test.dart
import 'package:eduai/core/connectivity/connectivity_service.dart';
import 'package:eduai/core/consent/minor_mode.dart';
import 'package:eduai/core/database/app_database.dart';
import 'package:eduai/core/providers/core_providers.dart';
import 'package:eduai/core/strings/app_strings.dart';
import 'package:eduai/features/email_validation/presentation/email_verification_dialog.dart';
import 'package:eduai/features/email_validation/providers/email_validation_providers.dart';
import 'package:eduai/widgets/shell_banners.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

UsersTableData _user({required String email}) {
  final now = DateTime(2026, 1, 1);
  return UsersTableData(
    id: 'u1',
    email: email,
    name: 'Veselý mrož',
    avatarIndex: 0,
    selectedSubjects: '[0]',
    isEmailValidated: false,
    isActive: true,
    syncStatus: 0,
    createdAt: now,
    updatedAt: now,
  );
}

/// An anonymous guest — `createGuestUser()` writes an empty e-mail.
final _guest = _user(email: '');

/// Registered, e-mail not confirmed yet (e.g. verification skipped offline).
final _unverified = _user(email: 'michal@example.com');

/// Offline, so the unverified user's tap stops at the SnackBar instead of
/// standing up the verification dialog's repository.
class _OfflineConn implements ConnectivityService {
  @override
  Future<bool> get isOnline async => false;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  late int registerTaps;

  Future<void> pumpPhoneBanners(
    WidgetTester tester, {
    required UsersTableData user,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    registerTaps = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          activeUserStreamProvider.overrideWith((ref) => Stream.value(user)),
          showEmailValidationBannerProvider.overrideWithValue(true),
          minorModeProvider
              .overrideWith((ref) => MinorModeNotifier()..state = false),
          connectivityServiceProvider.overrideWithValue(_OfflineConn()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ShellBanners(
              onLogout: () {},
              onRegisterTap: () => registerTaps++,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets(
      "a guest's banner opens the sign-up the sidebar card opens, not a dialog",
      (tester) async {
    await pumpPhoneBanners(tester, user: _guest);

    await tester.tap(find.text(AppStrings.bannerGuestMessage));
    await tester.pumpAndSettle();

    expect(registerTaps, 1);
    expect(find.byType(EmailVerificationDialog), findsNothing);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('an unverified e-mail still verifies in place', (tester) async {
    // Not a registration — the account exists. Their banner keeps its own
    // flow (here: the offline notice in front of the verification dialog).
    await pumpPhoneBanners(tester, user: _unverified);

    await tester.tap(find.text(AppStrings.bannerVerifyMessage));
    await tester.pumpAndSettle();

    expect(registerTaps, 0);
    expect(find.text(AppStrings.bannerOfflineMessage), findsOneWidget);
  });
}
