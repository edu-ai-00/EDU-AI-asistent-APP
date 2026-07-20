import 'oauth_provider.dart';

class OAuthClientResult {
  OAuthClientResult({
    required this.provider,
    required this.idToken,
    this.authorizationCode,
    this.email,
    this.fullName,
  });

  final OAuthProvider provider;
  final String idToken;
  final String? authorizationCode;
  final String? email;
  final String? fullName;
}
