import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'apple_oauth_client.dart';
import 'google_oauth_client.dart';
import 'microsoft_oauth_client.dart';

export 'apple_oauth_client.dart';
export 'google_oauth_client.dart';
export 'microsoft_oauth_client.dart';
export 'oauth_payload.dart';
export 'oauth_provider.dart';

/// Shared navigator key used by [MicrosoftOAuthClient] (aad_oauth) and wired
/// into GoRouter so the same navigator is used throughout the app.
final oauthNavigatorKeyProvider = Provider<GlobalKey<NavigatorState>>(
  (_) => GlobalKey<NavigatorState>(),
);

final appleOAuthClientProvider = Provider<AppleOAuthClient>(
  (_) => AppleOAuthClient(),
);

final googleOAuthClientProvider = Provider<GoogleOAuthClient>((ref) {
  const webClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
  return GoogleOAuthClient(webClientId: webClientId);
});

/// Redirect URI must exactly match a redirect registered on the Azure app.
/// Each platform has its own: Android uses the MSAL signature-hash URI, iOS the
/// bundle custom scheme, web the hosted callback. aad_oauth runs an in-app
/// webview and only compares this string against the redirect — the OS-level
/// BrowserTabActivity/App Link path (native MSAL) is never used.
String _microsoftRedirectUri() {
  if (kIsWeb) return 'https://app.edu-ai.eu/auth';
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return 'msauth://com.eduai.eduaiapp/VgQe1EefC0xgKDQ7RURSzlEeoVM%3D';
    case TargetPlatform.iOS:
      return 'msauth.com.eduai.eduaiapp://auth';
    default:
      return 'msauth.com.eduai.eduaiapp://auth';
  }
}

final microsoftOAuthClientProvider = Provider<MicrosoftOAuthClient>((ref) {
  const clientId = String.fromEnvironment('MICROSOFT_CLIENT_ID');
  const tenantId = String.fromEnvironment(
    'MICROSOFT_TENANT_ID',
    defaultValue: 'common',
  );
  return MicrosoftOAuthClient(
    clientId: clientId,
    tenantId: tenantId,
    redirectUri: _microsoftRedirectUri(),
    navigatorKey: ref.read(oauthNavigatorKeyProvider),
  );
});
