// Regression test for BR-WR4C8P.
//
// Practice cards used to be created only when a lesson was completed, so a
// guest who logged into an account kept only the cards from their guest
// session (e.g. 7) and never gained the account's full configured set (e.g.
// 10). `PracticeRepository.seedCardsFromCourse` fixes the "missing blocks" half
// of that bug: it materialises a practice card for EVERY default_practice block
// of a course, independent of lesson completion, and marks each pending so the
// sync layer uploads them.
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eduai/core/database/app_database.dart';
import 'package:eduai/data/repositories/practice_repository.dart';
import 'package:eduai/models/course_model.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  test(
      'seedCardsFromCourse creates one card per default_practice block, '
      'idempotently, and marks them active + pending for sync', () async {
    // Start from a real bundled course (the fixture ships with no practice
    // blocks) and flag three lesson-referenced blocks as default_practice.
    final data = jsonDecode(
      File('assets/courses/EDU_ONBOARDING_APP.json').readAsStringSync(),
    ) as Map<String, dynamic>;

    final definedIds = {
      for (final b in (data['blocks'] as List)) (b as Map)['block_id'] as String,
    };
    final referenced = <String>[];
    for (final l in (data['lessons'] as List)) {
      for (final ref in ((l as Map)['blocks'] as List? ?? const [])) {
        final bid = (ref as Map)['block_id'] as String?;
        if (bid != null && definedIds.contains(bid) && !referenced.contains(bid)) {
          referenced.add(bid);
        }
      }
    }
    expect(referenced.length, greaterThanOrEqualTo(3),
        reason: 'fixture must reference at least 3 defined blocks');

    final flagged = referenced.take(3).toSet();
    for (final b in (data['blocks'] as List)) {
      if (flagged.contains((b as Map)['block_id'])) {
        b['default_practice'] = true;
      }
    }

    const userId = 'user-1';
    final course = Course.fromJsonData(id: 'course-1', data: data);
    final repo = PracticeRepository(db: db);

    // The model must agree exactly 3 blocks are default_practice.
    expect(course.getDefaultPracticeBlocks().length, 3);

    // First seed creates all 3 — regardless of any lesson-completion state.
    final created = await repo.seedCardsFromCourse(userId: userId, course: course);
    expect(created, 3);

    // They are active, so the practice queue (which reads active cards) shows them.
    final active = await db.getActivePracticeCards(userId);
    expect(active.map((c) => c.blockId).toSet(), flagged);

    // They are pending, so _pushPracticeCards will upload them to the account.
    final pending = await db.getPendingSyncPracticeCards();
    expect(pending.map((c) => c.blockId).toSet(), flagged);

    // Re-seeding is a no-op — repeated syncs must never duplicate cards.
    final createdAgain =
        await repo.seedCardsFromCourse(userId: userId, course: course);
    expect(createdAgain, 0);
    expect((await db.getActivePracticeCards(userId)).length, 3);
  });
}
