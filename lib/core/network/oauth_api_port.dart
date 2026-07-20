import 'api_client.dart';

/// Minimal port consumed by [OauthRepository].
/// Placing this in core/network avoids circular imports between
/// data/repositories and core/network.
abstract interface class OAuthApiPort {
  Future<ApiResult<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    T Function(dynamic)? fromJson,
  });
}
