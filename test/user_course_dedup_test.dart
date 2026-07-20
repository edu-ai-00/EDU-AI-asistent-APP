// Regression test for BR-JUQZPY: "Nepodařilo se aktualizovat kurz: Bad state:
// Too many elements".
//
// Cause: the course-level dedup migration re-pointed a user's enrollment from a
// duplicate course row onto the keeper course row WITHOUT collapsing, producing
// two user_courses rows with the same (userId, courseId). Any later lookup via
// getUserCourseByUserAndCourse used drift's getSingleOrNull(), which throws
// "Too many elements" on more than one row — surfacing as the course-update
// error in the iOS app.
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eduai/core/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> insertCourse(String id, String courseId, {int? serverId}) {
    return db.into(db.coursesTable).insert(CoursesTableCompanion(
          id: Value(id),
          courseId: Value(courseId),
          name: Value('Course $id'),
          serverId: Value(serverId),
        ));
  }

  Future<void> insertEnrollment(String id, String userId, String courseId,
      {int? serverId,
      DateTime? updatedAt,
      String? status,
      int? progressPercent,
      int? completedLessons}) {
    return db.into(db.userCoursesTable).insert(UserCoursesTableCompanion(
          id: Value(id),
          userId: Value(userId),
          courseId: Value(courseId),
          serverId: Value(serverId),
          status: status != null ? Value(status) : const Value.absent(),
          progressPercent: progressPercent != null
              ? Value(progressPercent)
              : const Value.absent(),
          completedLessons: completedLessons != null
              ? Value(completedLessons)
              : const Value.absent(),
          updatedAt:
              updatedAt != null ? Value(updatedAt) : const Value.absent(),
        ));
  }

  test('getUserCourseByUserAndCourse tolerates duplicate rows', () async {
    // Two enrollments for the same (user, course) — the corrupt state that
    // used to throw "Too many elements".
    await insertCourse('course-keeper', 'MATH_5', serverId: 10);
    await insertEnrollment('uc-local', 'user-1', 'course-keeper');
    await insertEnrollment('uc-server', 'user-1', 'course-keeper', serverId: 99);

    final uc = await db.getUserCourseByUserAndCourse('user-1', 'course-keeper');

    expect(uc, isNotNull, reason: 'must not throw on duplicates');
    expect(uc!.serverId, 99,
        reason: 'prefer the server-linked enrollment when duplicates exist');
  });

  test('deduplicateCourses collapses enrollments instead of colliding',
      () async {
    // A local-only copy and a server-linked copy of the same course string.
    await insertCourse('course-local', 'MATH_5');
    await insertCourse('course-server', 'MATH_5', serverId: 10);

    // User is enrolled in BOTH copies.
    await insertEnrollment('uc-on-local', 'user-1', 'course-local');
    await insertEnrollment('uc-on-server', 'user-1', 'course-server',
        serverId: 99);

    final removed = await db.deduplicateCourses();
    expect(removed, 1, reason: 'the local-only course copy is removed');

    // Exactly one enrollment must remain for (user, keeper) — no collision.
    final keeper = await db.getCourseByFieldCourseId('MATH_5');
    final enrollments = await (db.select(db.userCoursesTable)
          ..where((uc) =>
              uc.userId.equals('user-1') & uc.courseId.equals(keeper!.id)))
        .get();
    expect(enrollments, hasLength(1),
        reason: 'dedup must not create duplicate (userId, courseId) rows');

    // And the hardened lookup still works after the migration.
    final uc = await db.getUserCourseByUserAndCourse('user-1', keeper!.id);
    expect(uc, isNotNull);
  });

  // BR-MFZF5R: "duplicitní kurz po aktualizaci" — after a course update the
  // background user/courses sync minted a second enrollment because its lookup
  // was pinned to one local course row while the enrollment lived on a twin
  // course row (same logical course, different local id). These cover both the
  // prevention (identity lookup) and the cleanup (enrollment dedup).

  test('findUserCourseByCourseIdentity matches enrollment via a sibling course '
      'row sharing the server course id', () async {
    // Two local course rows for the same server course (serverId 10) — the
    // twin-row state a version update can leave behind.
    await insertCourse('course-old', 'INTRO_V1', serverId: 10);
    await insertCourse('course-new', 'INTRO_V2', serverId: 10);
    // The user's real (completed) enrollment lives on the OLD row.
    await insertEnrollment('uc-real', 'user-1', 'course-old',
        status: 'completed', progressPercent: 100);

    // Sync resolves the incoming record to the NEW row. A plain
    // (userId, newRow.id) lookup misses; identity lookup must still find it.
    final byNewFk =
        await db.getUserCourseByUserAndCourse('user-1', 'course-new');
    expect(byNewFk, isNull, reason: 'plain FK lookup cannot see the twin');

    final found = await db.findUserCourseByCourseIdentity('user-1',
        serverId: 10, courseId: 'INTRO_V2');
    expect(found, isNotNull, reason: 'identity lookup must find the enrollment');
    expect(found!.id, 'uc-real');
  });

  test('deduplicateUserCourses collapses twin enrollments, keeping the richest',
      () async {
    // Twin course rows for the same server course.
    await insertCourse('course-old', 'INTRO_V1', serverId: 10);
    await insertCourse('course-new', 'INTRO_V2', serverId: 10);
    // The completed enrollment plus a fresh empty twin from the buggy sync.
    await insertEnrollment('uc-completed', 'user-1', 'course-old',
        status: 'completed', progressPercent: 100, completedLessons: 10);
    await insertEnrollment('uc-empty', 'user-1', 'course-new',
        status: 'downloaded', progressPercent: 0, completedLessons: 0);

    final removed = await db.deduplicateUserCourses('user-1');
    expect(removed, 1, reason: 'the empty twin enrollment is removed');

    final remaining = await db.getUserCourses('user-1');
    expect(remaining, hasLength(1), reason: 'exactly one card must remain');
    expect(remaining.first.id, 'uc-completed',
        reason: 'progress must never be lost to the empty twin');
  });

  test('deduplicateUserCourses leaves distinct courses untouched', () async {
    await insertCourse('course-a', 'A', serverId: 1);
    await insertCourse('course-b', 'B', serverId: 2);
    await insertEnrollment('uc-a', 'user-1', 'course-a');
    await insertEnrollment('uc-b', 'user-1', 'course-b');

    final removed = await db.deduplicateUserCourses('user-1');
    expect(removed, 0);
    expect(await db.getUserCourses('user-1'), hasLength(2));
  });
}
