// Regression test for BR-6CXZH5: the catalog pull asked
// GET /api/courses/check-updates?since=2026-11-11T15:12:12.000 for a course
// the server last changed at 14:12:12 UTC — local Prague time with no offset.
//
// Drift stores DateTime columns as unix seconds and reads them back as local
// time, so the newest `serverUpdatedAt` comes out of the database non-UTC and
// `toIso8601String()` drops the zone. The API runs in UTC and read the cursor
// as UTC, one or two hours late, so a course edited in that window never came
// down this path.
//
// Fix: the cursor is sent as `toUtc().toIso8601String()`, like every other
// timestamp the sync engine sends.
//
//   flutter test test/course_check_updates_since_test.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eduai/core/connectivity/connectivity_service.dart';
import 'package:eduai/core/database/app_database.dart';
import 'package:eduai/core/network/api_client.dart';
import 'package:eduai/core/services/auth_token_storage.dart';
import 'package:eduai/core/sync/sync_service.dart';

/// Answers every request with an empty `data` list and records its query.
class _RecordingAdapter implements HttpClientAdapter {
  final List<Map<String, dynamic>> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(Map.of(options.queryParameters));
    return ResponseBody.fromString(
      jsonEncode({'data': <Map<String, dynamic>>[]}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ApiClient apiClient;
  late _RecordingAdapter adapter;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
    apiClient = ApiClient(
      AuthTokenStorage(prefs: await SharedPreferences.getInstance()),
    );
    adapter = _RecordingAdapter();
    apiClient.dio.httpClientAdapter = adapter;
  });

  tearDown(() => db.close());

  SyncService syncService() => SyncService(
        db: db,
        apiClient: apiClient,
        connectivity: ConnectivityService(),
      );

  Future<void> seedCourse(String courseId, DateTime serverUpdatedAt) {
    return db.upsertCourse(CoursesTableCompanion(
      id: Value('local-$courseId'),
      serverId: Value(courseId.hashCode),
      courseId: Value(courseId),
      name: Value(courseId),
      serverUpdatedAt: Value(serverUpdatedAt),
    ));
  }

  test('since is the newest server change, sent as UTC', () async {
    await seedCourse('OLDER', DateTime.utc(2026, 11, 10, 9, 30));
    await seedCourse('NEWEST', DateTime.utc(2026, 11, 11, 14, 12, 12));

    await syncService().debugPullCourseUpdates();

    expect(adapter.requests, [
      {'since': '2026-11-11T14:12:12.000Z'},
    ]);
  });

  test('without a known server change the whole catalog is asked for',
      () async {
    await syncService().debugPullCourseUpdates();

    expect(adapter.requests, [<String, dynamic>{}]);
  });
}
