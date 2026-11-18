// BR-FBF78W: app.edu-ai.eu opened in a phone or tablet browser went straight
// into the web build — nothing told the visitor the app exists in the stores.
// It now offers "Nainstalovat aplikaci" or "Zůstat v prohlížeči" first.
//
//   flutter test test/widgets/install_app_prompt_test.dart
import 'package:eduai/core/install_app/install_app_offer.dart';
import 'package:eduai/core/providers/core_providers.dart';
import 'package:eduai/core/strings/app_strings.dart';
import 'package:eduai/widgets/install_app_prompt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('shouldOfferInstallApp', () {
    bool offer({
      bool isWeb = true,
      TargetPlatform platform = TargetPlatform.iOS,
      bool standalone = false,
      bool answered = false,
      String path = '/',
    }) =>
        shouldOfferInstallApp(
          isWeb: isWeb,
          platform: platform,
          standalone: standalone,
          answered: answered,
          path: path,
        );

    test('a phone or tablet browser gets the offer', () {
      expect(offer(platform: TargetPlatform.iOS), isTrue);
      expect(offer(platform: TargetPlatform.android), isTrue);
    });

    test('a desktop browser does not — there is no store app for it', () {
      for (final platform in [
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.fuchsia,
      ]) {
        expect(offer(platform: platform), isFalse, reason: '$platform');
      }
    });

    test('the native app itself never offers itself', () {
      expect(offer(isWeb: false), isFalse);
    });

    test('a home-screen web app is not in a browser to stay in', () {
      expect(offer(standalone: true), isFalse);
    });

    test('once answered, the browser is not asked again', () {
      expect(offer(answered: true), isFalse);
    });

    test('every app route gets it, deep links included', () {
      for (final path in [
        '/',
        '/dash',
        '/pin/676767',
        '/course/676767',
        '/join/AB12',
        '/chat/skolnik',
      ]) {
        expect(offer(path: path), isTrue, reason: path);
      }
    });

    test('legal documents and guardian consent pages do not', () {
      for (final path in [
        '/terms',
        '/privacy/en',
        '/cookies',
        '/consent/confirm',
        '/consent/manage/abc',
      ]) {
        expect(offer(path: path), isFalse, reason: path);
      }
    });

    test('each platform goes to its own store', () {
      expect(installAppStoreUri(TargetPlatform.iOS).toString(), kAppStoreUrl);
      expect(
        installAppStoreUri(TargetPlatform.android).toString(),
        kPlayStoreUrl,
      );
      expect(installAppStoreUri(TargetPlatform.macOS), isNull);
    });
  });

  group('InstallAppPrompt', () {
    late SharedPreferences prefs;
    late List<Uri> launched;
    late int underneathTaps;

    Future<void> pumpPrompt(
      WidgetTester tester, {
      Map<String, Object> stored = const {},
      bool isWeb = true,
      String path = '/',
    }) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues(stored);
      prefs = await SharedPreferences.getInstance();
      launched = [];
      underneathTaps = 0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: MaterialApp(
            builder: (context, child) => InstallAppPrompt(
              isWeb: isWeb,
              isStandalone: () => false,
              path: path,
              launchStore: (uri) async {
                launched.add(uri);
                return true;
              },
              child: child!,
            ),
            home: Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => underneathTaps++,
                  child: const Text('underneath'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    Finder installButton() => find.text(AppStrings.installAppPromptInstall);
    Finder stayButton() => find.text(AppStrings.installAppPromptStay);

    testWidgets(
      'a phone browser is offered the app and has to choose first',
      (tester) async {
        await pumpPrompt(tester);

        expect(find.text(AppStrings.installAppPromptTitle), findsOneWidget);
        expect(installButton(), findsOneWidget);
        expect(stayButton(), findsOneWidget);

        // Modal: the app underneath does not take taps until answered.
        await tester.tap(find.text('underneath'), warnIfMissed: false);
        await tester.pump();
        expect(underneathTaps, 0);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );

    testWidgets(
      '"Zůstat v prohlížeči" closes it for good on this browser',
      (tester) async {
        await pumpPrompt(tester);

        await tester.tap(stayButton());
        await tester.pump();

        expect(installButton(), findsNothing);
        expect(launched, isEmpty);
        expect(prefs.getBool(kInstallAppPromptAnsweredKey), isTrue);

        await tester.tap(find.text('underneath'));
        expect(underneathTaps, 1);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );

    testWidgets(
      '"Nainstalovat aplikaci" on an iPhone or iPad opens the App Store',
      (tester) async {
        await pumpPrompt(tester);

        await tester.tap(installButton());
        await tester.pump();

        expect(launched, [Uri.parse(kAppStoreUrl)]);
        expect(installButton(), findsNothing);
        expect(prefs.getBool(kInstallAppPromptAnsweredKey), isTrue);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );

    testWidgets(
      '"Nainstalovat aplikaci" on Android opens Google Play',
      (tester) async {
        await pumpPrompt(tester);

        await tester.tap(installButton());
        await tester.pump();

        expect(launched, [Uri.parse(kPlayStoreUrl)]);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );

    testWidgets(
      'a browser that already answered goes straight into the app',
      (tester) async {
        await pumpPrompt(
          tester,
          stored: {kInstallAppPromptAnsweredKey: true},
        );

        expect(installButton(), findsNothing);
        await tester.tap(find.text('underneath'));
        expect(underneathTaps, 1);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );

    testWidgets(
      'the store app itself shows nothing',
      (tester) async {
        await pumpPrompt(tester, isWeb: false);

        expect(installButton(), findsNothing);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );

    testWidgets(
      'a desktop browser shows nothing',
      (tester) async {
        await pumpPrompt(tester);

        expect(installButton(), findsNothing);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    testWidgets(
      'a parent opening the consent link from an e-mail is not offered it',
      (tester) async {
        await pumpPrompt(tester, path: '/consent/confirm');

        expect(installButton(), findsNothing);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  });
}
