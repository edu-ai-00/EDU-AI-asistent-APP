import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:eduai/core/network/api_client.dart';
import 'package:eduai/core/network/api_interceptors.dart';
import 'package:eduai/core/services/auth_token_storage.dart';
import 'package:eduai/core/util/device_kind.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Dio adapter that never hits the network and remembers the headers of the
/// last request it was handed.
class _CapturingAdapter implements HttpClientAdapter {
  Map<String, dynamic>? headers;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    headers = Map.of(options.headers);
    return ResponseBody.fromString(
      '{}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

Future<Map<String, dynamic>> _headersOf(Dio dio) async {
  final adapter = _CapturingAdapter();
  dio.httpClientAdapter = adapter;
  await dio.post<dynamic>('/api/guest/register');
  return adapter.headers!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // BR-CMA88Y: the server records the device of an account's first sign-in
  // from these headers, for the admin student detail.
  test('every request names the device the app runs on', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
      ..interceptors.add(DeviceInterceptor(
        device: () => const DeviceKind(platform: 'android', type: 'tablet'),
      ));

    final headers = await _headersOf(dio);

    expect(headers['X-Device-Platform'], 'android');
    expect(headers['X-Device-Type'], 'tablet');
  });

  test('an unknown form factor sends the platform alone', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
      ..interceptors.add(DeviceInterceptor(
        device: () => const DeviceKind(platform: 'ios'),
      ));

    final headers = await _headersOf(dio);

    expect(headers['X-Device-Platform'], 'ios');
    expect(headers.containsKey('X-Device-Type'), isFalse);
  });

  test('the API client sends the device with its requests', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final client = ApiClient(AuthTokenStorage(prefs: prefs));

    final headers = await _headersOf(client.dio);

    expect(headers['X-Device-Platform'], DeviceKind.current().platform);
  });
}
