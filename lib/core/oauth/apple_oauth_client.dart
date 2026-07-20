import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'oauth_payload.dart';
import 'oauth_provider.dart';

class AppleOAuthClient {
  Future<OAuthClientResult?> signIn() async {
    final AuthorizationCredentialAppleID credential;
    try {
      credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      // User dismissed the sheet — treat as a cancel (null), matching the
      // Google/Microsoft clients. Real failures still propagate.
      if (e.code == AuthorizationErrorCode.canceled) return null;
      rethrow;
    }

    final token = credential.identityToken;
    if (token == null) return null;

    final fullName = [credential.givenName, credential.familyName]
        .where((s) => s != null && s.isNotEmpty)
        .join(' ')
        .trim();

    return OAuthClientResult(
      provider: OAuthProvider.apple,
      idToken: token,
      authorizationCode: credential.authorizationCode,
      email: credential.email,
      fullName: fullName.isEmpty ? null : fullName,
    );
  }
}
