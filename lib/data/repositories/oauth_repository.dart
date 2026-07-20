import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_endpoints.dart';
import '../../core/network/oauth_api_port.dart';
import '../../core/oauth/oauth_payload.dart';
import '../../core/oauth/oauth_provider.dart';
import '../../core/providers/core_providers.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Result model
// ═══════════════════════════════════════════════════════════════════════════

class OAuthExchangeResult {
  OAuthExchangeResult({
    required this.token,
    required this.tokenType,
    required this.expiresAt,
    required this.sharedDevice,
    required this.sessionStartedAt,
    required this.user,
    required this.isNewUser,
    required this.profileSetupRequired,
  });

  final String token;
  final String tokenType;
  final String? expiresAt;
  final bool sharedDevice;
  final String? sessionStartedAt;
  final Map<String, dynamic> user;
  final bool isNewUser;
  final bool profileSetupRequired;
}

// ═══════════════════════════════════════════════════════════════════════════
// Exception
// ═══════════════════════════════════════════════════════════════════════════

class OAuthExchangeException implements Exception {
  OAuthExchangeException(this.message);
  final String message;
  @override
  String toString() => 'OAuthExchangeException: $message';
}

// ═══════════════════════════════════════════════════════════════════════════
// Repository
// ═══════════════════════════════════════════════════════════════════════════

class OauthRepository {
  OauthRepository(this._api);
  final OAuthApiPort _api;

  Future<OAuthExchangeResult> exchange(
    OAuthClientResult input, {
    bool sharedDevice = false,
  }) async {
    final path = switch (input.provider) {
      OAuthProvider.apple => ApiEndpoints.oauthApple,
      OAuthProvider.google => ApiEndpoints.oauthGoogle,
      OAuthProvider.microsoft => ApiEndpoints.oauthMicrosoft,
    };

    final body = <String, dynamic>{'shared_device': sharedDevice};

    if (input.provider == OAuthProvider.apple) {
      body['identity_token'] = input.idToken;
      if (input.authorizationCode != null) {
        body['authorization_code'] = input.authorizationCode;
      }
      if (input.fullName != null) {
        body['user'] = {'name': input.fullName};
      }
    } else {
      body['id_token'] = input.idToken;
    }

    final response =
        await _api.post<Map<String, dynamic>>(path, data: body);

    if (!response.isSuccess || response.data == null) {
      throw OAuthExchangeException(response.error ?? 'OAuth exchange failed');
    }

    final d = response.data!;
    return OAuthExchangeResult(
      token: d['token'] as String,
      tokenType: (d['token_type'] as String?) ?? 'Bearer',
      expiresAt: d['expires_at'] as String?,
      sharedDevice: (d['shared_device'] as bool?) ?? sharedDevice,
      sessionStartedAt: d['session_started_at'] as String?,
      user: d['user'] as Map<String, dynamic>,
      isNewUser: (d['is_new_user'] as bool?) ?? false,
      profileSetupRequired: (d['profile_setup_required'] as bool?) ?? false,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Riverpod provider
// ═══════════════════════════════════════════════════════════════════════════

final oauthRepositoryProvider = Provider<OauthRepository>((ref) {
  return OauthRepository(ref.watch(apiClientProvider));
});
