import 'package:dio/dio.dart';

import '../services/auth_token_storage.dart';
import '../services/session_meta.dart';
import 'api_endpoints.dart';
import 'api_interceptors.dart';

/// Result wrapper for API responses.
class ApiResult<T> {
  final T? data;
  final String? error;
  final int? statusCode;

  const ApiResult._({this.data, this.error, this.statusCode});

  factory ApiResult.success(T data, {int? statusCode}) =>
      ApiResult._(data: data, statusCode: statusCode);

  factory ApiResult.failure(String error, {int? statusCode}) =>
      ApiResult._(error: error, statusCode: statusCode);

  bool get isSuccess => error == null;
  bool get isFailure => error != null;
}

/// Configured Dio client for API communication.
class ApiClient {
  late final Dio _dio;
  final AuthTokenStorage _tokens;
  final SessionMeta? _session;

  ApiClient(
    this._tokens, {
    SessionMeta? session,
    bool enableLogging = false,
  }) : _session = session {
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiEndpoints.baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    // Add interceptors in order. Token rotation must come before AuthInterceptor
    // so the rotated token is attached to the in-flight request.
    final session = _session;
    if (session != null) {
      _dio.interceptors.add(TokenRotationInterceptor(
        dio: _dio,
        tokens: _tokens,
        session: session,
      ));
    }
    _dio.interceptors.add(AuthInterceptor(_tokens));
    _dio.interceptors.add(RetryInterceptor(_dio));

    if (enableLogging) {
      _dio.interceptors.add(LoggingInterceptor());
    }
  }

  /// Session metadata accessor for callers that need to read shared_device
  /// flag, expiry, or update activity timestamps.
  SessionMeta? get session => _session;

  /// The underlying Dio instance for direct access if needed.
  Dio get dio => _dio;

  // ═══════════════════════════════════════════════════════════════════════════
  // Generic HTTP Methods
  // ═══════════════════════════════════════════════════════════════════════════

  /// Perform a GET request.
  Future<ApiResult<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    T Function(dynamic)? fromJson,
  }) async {
    try {
      final response = await _dio.get(
        path,
        queryParameters: queryParameters,
      );

      final data =
          fromJson != null ? fromJson(response.data) : response.data as T;

      return ApiResult.success(data, statusCode: response.statusCode);
    } on DioException catch (e) {
      return _handleError(e);
    } catch (e) {
      return ApiResult.failure(e.toString());
    }
  }

  /// Perform a POST request.
  Future<ApiResult<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    T Function(dynamic)? fromJson,
  }) async {
    try {
      final response = await _dio.post(
        path,
        data: data,
        queryParameters: queryParameters,
      );

      final result =
          fromJson != null ? fromJson(response.data) : response.data as T;

      return ApiResult.success(result, statusCode: response.statusCode);
    } on DioException catch (e) {
      return _handleError(e);
    } catch (e) {
      return ApiResult.failure(e.toString());
    }
  }

  /// Perform a PUT request.
  Future<ApiResult<T>> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    T Function(dynamic)? fromJson,
  }) async {
    try {
      final response = await _dio.put(
        path,
        data: data,
        queryParameters: queryParameters,
      );

      final result =
          fromJson != null ? fromJson(response.data) : response.data as T;

      return ApiResult.success(result, statusCode: response.statusCode);
    } on DioException catch (e) {
      return _handleError(e);
    } catch (e) {
      return ApiResult.failure(e.toString());
    }
  }

  /// Perform a DELETE request.
  Future<ApiResult<T>> delete<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    T Function(dynamic)? fromJson,
  }) async {
    try {
      final response = await _dio.delete(
        path,
        data: data,
        queryParameters: queryParameters,
      );

      final result =
          fromJson != null ? fromJson(response.data) : response.data as T;

      return ApiResult.success(result, statusCode: response.statusCode);
    } on DioException catch (e) {
      return _handleError(e);
    } catch (e) {
      return ApiResult.failure(e.toString());
    }
  }

  /// Handle Dio errors and convert to ApiResult.
  ApiResult<T> _handleError<T>(DioException e) {
    String message;
    final statusCode = e.response?.statusCode;

    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        message = 'Connection timeout. Please check your internet connection.';
        break;
      case DioExceptionType.connectionError:
        message = 'No internet connection.';
        break;
      case DioExceptionType.badResponse:
        message = _extractErrorMessage(e.response);
        break;
      case DioExceptionType.cancel:
        message = 'Request was cancelled.';
        break;
      default:
        message = e.message ?? 'An unexpected error occurred.';
    }

    return ApiResult.failure(message, statusCode: statusCode);
  }

  /// Extract error message from response body.
  String _extractErrorMessage(Response? response) {
    if (response?.data == null) {
      return 'Server error: ${response?.statusCode}';
    }

    final data = response!.data;

    if (data is Map) {
      // Laravel validation errors.
      if (data['errors'] != null) {
        final errors = data['errors'] as Map;
        final firstError = errors.values.first;
        if (firstError is List && firstError.isNotEmpty) {
          return firstError.first.toString();
        }
      }

      // Standard error message.
      if (data['message'] != null) {
        return data['message'].toString();
      }
    }

    return 'Server error: ${response.statusCode}';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // User Profile Methods
  // ═══════════════════════════════════════════════════════════════════════════

  /// Update user name.
  Future<ApiResult<Map<String, dynamic>>> updateUserName(String name) {
    return put<Map<String, dynamic>>(
      ApiEndpoints.updateProfile,
      data: {'name': name},
      fromJson: (data) => data as Map<String, dynamic>,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Auth Token Management
  // ═══════════════════════════════════════════════════════════════════════════

  /// Store the auth token.
  Future<void> setAuthToken(String token) async {
    await _tokens.setToken(token);
  }

  /// Get the current auth token.
  String? getAuthToken() => _tokens.token;

  /// Clear the auth token (logout).
  Future<void> clearAuthToken() async {
    await _tokens.clearToken();
  }

  /// Check if user is authenticated.
  bool get isAuthenticated => _tokens.isAuthenticated;
}
