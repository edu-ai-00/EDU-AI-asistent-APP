import 'dart:async';

import 'package:dio/dio.dart';

import '../services/auth_token_storage.dart';
import '../services/session_meta.dart';
import 'api_endpoints.dart';

/// Keys for storing auth data.
class AuthStorageKeys {
  AuthStorageKeys._();

  static const String token = 'auth_token';
  static const String userId = 'user_id';
}

/// Interceptor that adds the Bearer token to authenticated requests.
class AuthInterceptor extends Interceptor {
  final AuthTokenStorage _tokens;

  AuthInterceptor(this._tokens);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = _tokens.token;

    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }

    options.headers['Accept'] = 'application/json';

    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // 401 → token expired or revoked; clear local copy.
    if (err.response?.statusCode == 401) {
      _tokens.clearToken();
    }

    handler.next(err);
  }
}

/// Rotates the access token before it expires for shared-device sessions
/// (and persistent sessions, which simply rotate before the 30-day mark).
///
/// Triggered by [SessionMeta.needsRotation]. Concurrent requests share a
/// single in-flight rotate via [_rotating] so we don't spam /api/auth/refresh.
/// A 401 from /api/auth/refresh terminates the session — handled upstream
/// by the existing AuthInterceptor onError clearing the token.
class TokenRotationInterceptor extends Interceptor {
  final Dio _dio;
  final AuthTokenStorage _tokens;
  final SessionMeta _session;
  Future<void>? _rotating;

  TokenRotationInterceptor({
    required Dio dio,
    required AuthTokenStorage tokens,
    required SessionMeta session,
  })  : _dio = dio,
        _tokens = tokens,
        _session = session;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    // Never rotate while calling rotate (avoid recursion) or when not authed.
    final isRotateCall = options.path.endsWith(ApiEndpoints.authRefresh);
    final isLogoutCall = options.path.endsWith(ApiEndpoints.logout);

    if (!isRotateCall && !isLogoutCall && (_tokens.token ?? '').isNotEmpty) {
      // Touch activity for any authenticated user-driven call (interceptor
      // runs only for app-issued requests).
      await _session.touchActivity();

      if (_session.needsRotation()) {
        try {
          await _ensureRotated();
        } catch (_) {
          // Rotation failed — let the original request fly. If token is
          // truly dead the server will 401 and AuthInterceptor clears it.
        }
      }
    }

    handler.next(options);
  }

  Future<void> _ensureRotated() {
    return _rotating ??= _doRotate().whenComplete(() => _rotating = null);
  }

  Future<void> _doRotate() async {
    final response = await _dio.post(ApiEndpoints.authRefresh);
    final data = response.data;
    if (data is Map<String, dynamic>) {
      final newToken = data['token'] as String?;
      if (newToken != null && newToken.isNotEmpty) {
        await _tokens.setToken(newToken);
      }
      await _session.applyFromAuthResponse(data);
    }
  }
}

/// Interceptor for logging requests and responses (debug mode).
class LoggingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    handler.next(err);
  }
}

/// Interceptor that handles retry logic for transient failures.
class RetryInterceptor extends Interceptor {
  final Dio _dio;
  final int _maxRetries;

  RetryInterceptor(this._dio, {int maxRetries = 1}) : _maxRetries = maxRetries;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final retryCount = (err.requestOptions.extra['retryCount'] as int?) ?? 0;

    final shouldRetry = _isRetryableError(err) && retryCount < _maxRetries;

    if (shouldRetry) {
      final delay = Duration(milliseconds: 1000 * (retryCount + 1));
      await Future.delayed(delay);

      final options = err.requestOptions;
      options.extra['retryCount'] = retryCount + 1;

      try {
        final response = await _dio.fetch(options);
        handler.resolve(response);
        return;
      } catch (_) {
        // Fall through.
      }
    }

    handler.next(err);
  }

  bool _isRetryableError(DioException err) {
    if (err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.sendTimeout ||
        err.type == DioExceptionType.receiveTimeout) {
      return true;
    }

    final statusCode = err.response?.statusCode;
    return statusCode != null && statusCode >= 500 && statusCode < 600;
  }
}
