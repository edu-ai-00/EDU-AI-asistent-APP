// BR-MKFPU6 — a finished entry quiz never reached the server.
//
// The last answer queues a progress write (`quiz_in_progress: true`) and starts
// a sync. While that PUT was on the wire, finishing the quiz queued the
// completion (`quiz_completed: true`). SyncQueue.enqueue merges a change into
// the entry still waiting for this record — and the entry being sent still
// waits until its request returns. The push then deleted the entry by id, so
// the merged completion went with it: the server kept the stale in-progress
// snapshot, and after a reload the course offered "Začít kvíz" again.
//
// The push now deletes the entry only while it still holds what was sent; a
// changed entry goes out on the next round.
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eduai/core/connectivity/connectivity_service.dart';
import 'package:eduai/core/database/app_database.dart';
import 'package:eduai/core/network/api_client.dart';
import 'package:eduai/core/services/auth_token_storage.dart';
import 'package:eduai/core/sync/sync_queue.dart';
import 'package:eduai/core/sync/sync_service.dart';
import 'package:eduai/core/sync/sync_status.dart';
import 'package:eduai/data/repositories/user_course_repository.dart';

const _userCourseId = 'uc-1';

/// Records every PUT body and answers 200. [onPut] runs before the response
/// goes back, i.e. while the request is still in flight.
class _RecordingAdapter implements HttpClientAdapter {
  final puts = <Map<String, dynamic>>[];
  Future<void> Function(int putIndex)? onPut;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.method == 'PUT') {
      final body = options.data is String
          ? jsonDecode(options.data as String) as Map<String, dynamic>
          : Map<String, dynamic>.from(options.data as Map);
      puts.add(body);
      await onPut?.call(puts.length - 1);
    }
    return ResponseBody.fromString(
      jsonEncode({'message': 'Progress updated'}),
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
  late UserCourseRepository repo;
  late SyncService sync;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final tokens = AuthTokenStorage(prefs: prefs);
    await tokens.setToken('test-token');
    apiClient = ApiClient(tokens);
    adapter = _RecordingAdapter();
    apiClient.dio.httpClientAdapter = adapter;

    await db.upsertCourse(const CoursesTableCompanion(
      id: Value('c-1'),
      serverId: Value(19),
      courseId: Value('DEMOKURZ02'),
      name: Value('Demo kurz'),
      data: Value('{"starts_with_quiz": true}'),
    ));
    await db.upsertUserCourse(const UserCoursesTableCompanion(
      id: Value(_userCourseId),
      serverId: Value(829),
      userId: Value('u-1'),
      courseId: Value('c-1'),
      status: Value('downloaded'),
    ));

    repo = UserCourseRepository(db: db, syncQueue: SyncQueue(db));
    sync = SyncService(
      db: db,
      apiClient: apiClient,
      connectivity: ConnectivityService(),
    );
  });

  tearDown(() => db.close());

  const lastAnswer = {
    'quiz_in_progress': true,
    'quiz_current_index': 2,
    'quiz_answered': 3,
  };
  const finished = {
    'quiz_in_progress': false,
    'quiz_answered': 3,
    'quiz_completed': true,
    'quiz_completed_at': '2026-11-11T15:08:06.520Z',
  };

  test('completion merged in while the last answer is on the wire still goes out',
      () async {
    await repo.updateProgress(id: _userCourseId, progressData: lastAnswer);

    // The quiz is finished while the last answer's PUT is in flight.
    adapter.onPut = (i) async {
      if (i == 0) {
        await repo.updateProgress(
          id: _userCourseId,
          status: UserCourseStatus.inProgress,
          progressData: finished,
        );
      }
    };

    await sync.debugPushChanges();

    expect(adapter.puts, hasLength(2),
        reason: 'the merged completion must be pushed, not dropped');
    expect(adapter.puts.first['progress_data']['quiz_in_progress'], isTrue);
    final last = adapter.puts.last;
    expect(last['progress_data']['quiz_completed'], isTrue);
    expect(last['progress_data']['quiz_in_progress'], isFalse);
    expect(last['status'], 'in_progress');

    expect(await SyncQueue(db).getPendingCount(), 0);
    final row = await db.getUserCourseById(_userCourseId);
    expect(row!.syncStatus, SyncStatus.synced.toInt());
  });

  test('an entry left unchanged is removed after a single PUT', () async {
    await repo.updateProgress(id: _userCourseId, progressData: finished);

    await sync.debugPushChanges();

    expect(adapter.puts, hasLength(1));
    expect(await SyncQueue(db).getPendingCount(), 0);
  });

  group('statusAfterCourseQuiz', () {
    test('only_quiz: the quiz finishes the course', () {
      expect(
        statusAfterCourseQuiz(
          courseData: {'only_quiz': true},
          currentStatus: 'downloaded',
        ),
        UserCourseStatus.completed,
      );
    });

    test('starts_with_quiz: the entry quiz starts the course', () {
      expect(
        statusAfterCourseQuiz(
          courseData: {'starts_with_quiz': true},
          currentStatus: 'downloaded',
        ),
        UserCourseStatus.inProgress,
      );
    });

    test('starts_with_quiz: a course already under way keeps its status', () {
      for (final status in ['in_progress', 'completed']) {
        expect(
          statusAfterCourseQuiz(
            courseData: {'starts_with_quiz': true},
            currentStatus: status,
          ),
          isNull,
          reason: status,
        );
      }
    });

    test('a regular course quiz leaves the status alone', () {
      expect(
        statusAfterCourseQuiz(courseData: {}, currentStatus: 'downloaded'),
        isNull,
      );
    });
  });
}
