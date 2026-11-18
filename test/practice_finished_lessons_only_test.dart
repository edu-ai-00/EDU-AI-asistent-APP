// Regression test for BR-B5QBBS.
//
// Opakování offered blocks from lessons the student had not finished: one from
// a lesson in progress, one from a lesson never opened. Both were blocks the
// author flagged for practice (default_practice), and the sync seeded a card
// for every such block of every enrolled course up front (BR-WR4C8P), so they
// were due from the moment the course was added. An author's practice block
// belongs in practice once its lesson is finished, which is when the lesson
// page seeds it.
//
// Two layers are covered here:
//   * the source: the sync seeds cards only for lessons the student finished;
//   * the offer: `lesson` cards seeded up front before the fix (and pulled back
//     from the account on the server) stay out of practice until their lesson
//     is finished. The rows are filtered, never deleted.
import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eduai/core/connectivity/connectivity_service.dart';
import 'package:eduai/core/database/app_database.dart';
import 'package:eduai/core/network/api_client.dart';
import 'package:eduai/core/services/auth_token_storage.dart';
import 'package:eduai/core/sync/sync_service.dart';
import 'package:eduai/data/repositories/practice_repository.dart';

const _userId = 'user-1';

Map<String, dynamic> _block(String id) => {
      'block_id': id,
      'type': 'display',
      'default_practice': true,
      'steps': [
        {'id': 's1', 'order': 1, 'type': 'text', 'content': 'Obsah $id'},
      ],
    };

/// Three lessons in free order, each holding one block flagged for practice.
final _courseData = jsonDecode(jsonEncode({
  'course_id': 'DEMO',
  'name': 'Demo',
  'open_all_lessons': true,
  'blocks': [_block('B1'), _block('B2'), _block('B3')],
  'lessons': [
    for (final n in [1, 2, 3])
      {
        'lesson_id': 'L$n',
        'name': 'Lekce $n',
        'blocks': [
          {'block_id': 'B$n', 'order': 1},
        ],
      },
  ],
})) as Map<String, dynamic>;

/// The reported state: lesson 1 finished, lesson 2 in progress, lesson 3 never
/// opened.
const _reportedProgress = {
  'lessons': {
    'L1': {'is_completed': true},
    'L2': {
      'completed_blocks': ['B0'],
      'current_block_index': 1,
    },
  },
};

Future<void> _insertCourse(AppDatabase db) {
  return db.upsertCourse(CoursesTableCompanion(
    id: const Value('c-local'),
    courseId: const Value('DEMO'),
    name: const Value('Demo'),
    data: Value(jsonEncode(_courseData)),
  ));
}

Future<void> _enroll(
  AppDatabase db, {
  required Map<String, dynamic> progress,
  int completedLessons = 1,
}) {
  return db.upsertUserCourse(UserCoursesTableCompanion(
    id: const Value('uc-1'),
    userId: const Value(_userId),
    courseId: const Value('c-local'),
    status: const Value('in_progress'),
    completedLessons: Value(completedLessons),
    totalLessons: const Value(3),
    progressDataJson: Value(jsonEncode(progress)),
  ));
}

Future<void> _insertCard(
  AppDatabase db, {
  required String blockId,
  required String lessonId,
  String courseId = 'c-local',
  String sourceType = 'lesson',
}) {
  return db.upsertPracticeCard(PracticeCardsTableCompanion(
    id: Value('card-$blockId'),
    userId: const Value(_userId),
    courseId: Value(courseId),
    lessonId: Value(lessonId),
    blockId: Value(blockId),
    sourceType: Value(sourceType),
  ));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late SyncService sync;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    sync = SyncService(
      db: db,
      apiClient: ApiClient(AuthTokenStorage(prefs: prefs)),
      connectivity: ConnectivityService(),
    );
    await _insertCourse(db);
  });

  tearDown(() => db.close());

  Future<Set<String>> activeBlockIds() async =>
      (await db.getActivePracticeCards(_userId)).map((c) => c.blockId).toSet();

  test(
      'the sync seeds practice blocks of finished lessons only, and the rest '
      'once their lesson is finished', () async {
    await _enroll(db, progress: _reportedProgress);

    await sync.debugSeedPracticeCards(_userId);
    expect(await activeBlockIds(), {'B1'},
        reason: 'lesson 2 is in progress and lesson 3 was never opened');

    await _enroll(db, completedLessons: 2, progress: {
      'lessons': {
        'L1': {'is_completed': true},
        'L2': {'is_completed': true},
      },
    });
    await sync.debugSeedPracticeCards(_userId);
    expect(await activeBlockIds(), {'B1', 'B2'});
  });

  test('a finished course seeds every practice block', () async {
    await db.upsertUserCourse(const UserCoursesTableCompanion(
      id: Value('uc-1'),
      userId: Value(_userId),
      courseId: Value('c-local'),
      status: Value('completed'),
      completedLessons: Value(3),
      totalLessons: Value(3),
      progressDataJson: Value('{}'),
    ));

    await sync.debugSeedPracticeCards(_userId);
    expect(await activeBlockIds(), {'B1', 'B2', 'B3'});
  });

  test(
      'cards already seeded for unfinished lessons are kept out of practice '
      'until the lesson is finished, and are not deleted', () async {
    await _enroll(db, progress: _reportedProgress);
    // Seeded up front before the fix, under either course id spelling.
    await _insertCard(db, blockId: 'B1', lessonId: 'L1');
    await _insertCard(db, blockId: 'B2', lessonId: 'L2', courseId: 'DEMO');
    await _insertCard(db, blockId: 'B3', lessonId: 'L3');
    // A student's own bookmark is not an author's practice block: it stays.
    await _insertCard(
        db, blockId: 'Q9', lessonId: 'L3', sourceType: 'bookmark');
    // Nothing on this device says how far the student got in a course whose
    // content is missing, so its card is left to the playable resolution.
    await _insertCard(
        db, blockId: 'X1', lessonId: 'L1', courseId: 'NOT_DOWNLOADED');

    final repo = PracticeRepository(db: db);
    Future<Set<String>> offered() async =>
        (await repo.getPracticeableCards(_userId)).map((c) => c.blockId).toSet();

    expect(await offered(), {'B1', 'Q9', 'X1'});
    expect((await repo.getActiveCards(_userId)).length, 5);

    await _enroll(db, completedLessons: 2, progress: {
      'lessons': {
        'L1': {'is_completed': true},
        'L3': {'is_completed': true},
      },
    });
    expect(await offered(), {'B1', 'B3', 'Q9', 'X1'});
  });
}
