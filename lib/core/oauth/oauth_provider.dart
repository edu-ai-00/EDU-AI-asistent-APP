enum OAuthProvider { apple, google, microsoft }

extension OAuthProviderX on OAuthProvider {
  String get wireName => switch (this) {
        OAuthProvider.apple => 'apple',
        OAuthProvider.google => 'google',
        OAuthProvider.microsoft => 'microsoft',
      };
}
