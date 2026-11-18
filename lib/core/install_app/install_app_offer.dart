import 'package:flutter/foundation.dart';

import '../../pages/legal/legal_page.dart' show legalSlugs;

/// The native app's store listings (BR-FBF78W). Same bundle id on both
/// platforms — `com.eduai.eduaiapp`.
const kAppStoreUrl = 'https://apps.apple.com/app/id6769472388';
const kPlayStoreUrl =
    'https://play.google.com/store/apps/details?id=com.eduai.eduaiapp';

/// SharedPreferences flag: the visitor already answered the "install the app
/// or stay in the browser" offer on this browser. Either answer counts — the
/// offer is made once, not on every visit.
const kInstallAppPromptAnsweredKey = 'install_app_prompt_answered';

/// Where "Install the app" leads on [platform], or null where there is no
/// store listing to offer.
Uri? installAppStoreUri(TargetPlatform platform) => switch (platform) {
      TargetPlatform.iOS => Uri.parse(kAppStoreUrl),
      TargetPlatform.android => Uri.parse(kPlayStoreUrl),
      _ => null,
    };

/// Whether a browser visit should be offered the native app instead
/// (BR-FBF78W).
///
/// Only a phone or tablet browser gets the offer — on the web build
/// [platform] comes from the browser, and Flutter reports an iPad that asks
/// for the desktop site as iOS too. Not when the web app already runs from
/// the home screen ([standalone]): "stay in the browser" means nothing there.
///
/// [path] is the URL the app was opened at. The legal documents and the
/// guardian consent pages are public pages, not the app — a parent confirming
/// consent from an e-mail has no use for a student's app — so they open
/// without the offer.
bool shouldOfferInstallApp({
  required bool isWeb,
  required TargetPlatform platform,
  required bool standalone,
  required bool answered,
  required String path,
}) {
  if (!isWeb || standalone || answered) return false;
  if (installAppStoreUri(platform) == null) return false;

  final segments = Uri.parse(path).pathSegments;
  if (segments.isEmpty) return true;
  final first = segments.first;
  return first != 'consent' && !legalSlugs.contains(first);
}
