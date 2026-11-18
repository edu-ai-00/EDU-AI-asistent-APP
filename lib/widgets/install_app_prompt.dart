import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/install_app/install_app_offer.dart';
import '../core/install_app/standalone_display.dart';
import '../core/providers/core_providers.dart';
import '../core/strings/app_strings.dart';
import '../core/theme/app_theme.dart';
import '../core/util/silent_log.dart';
import 'auth_buttons.dart';

/// Offers the native app when the web build is opened in a phone or tablet
/// browser: "Install the app" or "Stay in the browser" (BR-FBF78W).
///
/// Sits in `MaterialApp.builder`, above the Navigator, so no route push or
/// pop — the boot flow, a deep link opening its course — can cover or close
/// it. The visitor has to pick one of the two; whichever it is, the browser
/// remembers it and the offer is not made again. [shouldOfferInstallApp]
/// decides who gets it at all.
///
/// Everything but [child] is a test seam; the defaults are the real browser.
class InstallAppPrompt extends ConsumerStatefulWidget {
  final Widget child;
  final bool isWeb;
  final bool Function() isStandalone;

  /// URL path the app was opened at. Defaults to the browser's.
  final String? path;

  /// Opens the store listing. Defaults to the platform's URL launcher.
  final Future<bool> Function(Uri uri)? launchStore;

  const InstallAppPrompt({
    super.key,
    required this.child,
    this.isWeb = kIsWeb,
    this.isStandalone = isStandaloneDisplay,
    this.path,
    this.launchStore,
  });

  @override
  ConsumerState<InstallAppPrompt> createState() => _InstallAppPromptState();
}

class _InstallAppPromptState extends ConsumerState<InstallAppPrompt> {
  late bool _visible;

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(sharedPreferencesProvider);
    _visible = shouldOfferInstallApp(
      isWeb: widget.isWeb,
      platform: defaultTargetPlatform,
      standalone: widget.isStandalone(),
      answered: prefs.getBool(kInstallAppPromptAnsweredKey) ?? false,
      path: widget.path ?? Uri.base.path,
    );
  }

  void _answer() {
    setState(() => _visible = false);
    ref
        .read(sharedPreferencesProvider)
        .setBool(kInstallAppPromptAnsweredKey, true);
  }

  void _install() {
    final uri = installAppStoreUri(defaultTargetPlatform);
    if (uri != null) {
      // Called straight from the tap, before any await: Safari only lets a
      // page open a new window from inside the user's gesture.
      final launch = widget.launchStore ?? _launchExternal;
      launch(uri).catchError((Object e, StackTrace st) {
        silentLog('install_app_prompt:launch', e, st);
        return false;
      });
    }
    _answer();
  }

  static Future<bool> _launchExternal(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    if (!_visible) return widget.child;

    return Stack(
      children: [
        widget.child,
        const Positioned.fill(
          child: ModalBarrier(dismissible: false, color: Colors.black54),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: _OfferCard(onInstall: _install, onStay: _answer),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _OfferCard extends StatelessWidget {
  final VoidCallback onInstall;
  final VoidCallback onStay;

  const _OfferCard({required this.onInstall, required this.onStay});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: AppDecorations.radiusL,
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Icons.install_mobile_outlined,
              size: 40,
              color: AppColors.primaryDark,
            ),
            const SizedBox(height: 12),
            Text(
              AppStrings.installAppPromptTitle,
              style: AppTextStyles.heading3(),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              AppStrings.installAppPromptMessage,
              style: AppTextStyles.body(),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            AuthPrimaryButton(
              label: AppStrings.installAppPromptInstall,
              onPressed: onInstall,
            ),
            const SizedBox(height: 12),
            AuthSecondaryButton(
              label: AppStrings.installAppPromptStay,
              onPressed: onStay,
            ),
          ],
        ),
      ),
    );
  }
}
