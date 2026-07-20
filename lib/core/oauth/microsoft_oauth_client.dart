import 'package:aad_oauth/aad_oauth.dart';
import 'package:aad_oauth/model/config.dart';
import 'package:flutter/material.dart';
import 'oauth_payload.dart';
import 'oauth_provider.dart';

class MicrosoftOAuthClient {
  MicrosoftOAuthClient({
    required String clientId,
    required String tenantId,
    required String redirectUri,
    required GlobalKey<NavigatorState> navigatorKey,
  }) : _oauth = AadOAuth(Config(
          tenant: tenantId,
          clientId: clientId,
          scope: 'openid profile email',
          redirectUri: redirectUri,
          navigatorKey: navigatorKey,
        ));

  final AadOAuth _oauth;

  Future<OAuthClientResult?> signIn() async {
    // login() returns Either<Failure, Token>; we only need the side-effect of
    // populating the token cache — getIdToken() retrieves from that cache.
    final result = await _oauth.login();
    if (result.isLeft()) return null; // Failure (includes user-cancel)

    final idToken = await _oauth.getIdToken();
    if (idToken == null || idToken.isEmpty) return null;

    return OAuthClientResult(
      provider: OAuthProvider.microsoft,
      idToken: idToken,
    );
  }
}
