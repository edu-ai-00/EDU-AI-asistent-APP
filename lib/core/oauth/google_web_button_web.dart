import 'package:flutter/widgets.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:google_sign_in_web/google_sign_in_web.dart';

/// The Google Identity Services button, rendered by google_sign_in_web. A
/// click drives the sign-in flow; the result arrives on
/// `GoogleSignIn.instance.authenticationEvents` (see [GoogleOAuthClient]).
///
/// [GoogleOAuthClient.ensureInitialized] must have completed before this is
/// built, or the GIS SDK has no client ID to render against.
///
/// Google restricts how far the rendered button can be styled (branding
/// rules), so it can't perfectly match the custom Microsoft/Apple buttons.
/// The configuration below gets it as close as allowed: white outline theme,
/// large size, rounded, left-aligned logo, Czech "Sign in with Google" text.
/// GIS also hard-caps the width near 400px, so it stays a touch narrower.
Widget googleRenderedSignInButton() {
  final plugin = GoogleSignInPlatform.instance;
  if (plugin is GoogleSignInPlugin) {
    return plugin.renderButton(
      configuration: GSIButtonConfiguration(
        theme: GSIButtonTheme.outline,
        size: GSIButtonSize.large,
        shape: GSIButtonShape.rectangular,
        text: GSIButtonText.signinWith,
        logoAlignment: GSIButtonLogoAlignment.left,
        minimumWidth: 400,
        locale: 'cs',
      ),
    );
  }
  return const SizedBox.shrink();
}
