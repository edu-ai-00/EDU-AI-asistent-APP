import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/practice_repository.dart';
import '../../models/course_model.dart';
import '../database/app_database.dart';
import '../practice/practice_service.dart';
import 'core_providers.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Practice Repository Provider
// ═══════════════════════════════════════════════════════════════════════════════

/// Provider for the practice repository.
final practiceRepositoryProvider = Provider<PracticeRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return PracticeRepository(db: db);
});

// ═══════════════════════════════════════════════════════════════════════════════
// Practice Service Provider
// ═══════════════════════════════════════════════════════════════════════════════

/// Provider for the practice service.
final practiceServiceProvider = Provider<PracticeService>((ref) {
  final repo = ref.watch(practiceRepositoryProvider);
  return PracticeService(repo: repo);
});

// ═══════════════════════════════════════════════════════════════════════════════
// Practice Data Providers
// ═══════════════════════════════════════════════════════════════════════════════

/// Future provider for today's practice queue for the active user.
final practiceQueueProvider = FutureProvider<List<PracticeCardsTableData>>((ref) async {
  final user = await ref.watch(activeUserProvider.future);
  if (user == null) return [];

  final service = ref.watch(practiceServiceProvider);
  return service.generateQueue(user.id);
});

/// Resolves the practice queue to the actual, answerable content blocks.
///
/// A card row is only useful if its course/block can be loaded locally AND
/// the block is answerable (has a question or v2 steps). Cards that can't be
/// resolved — missing course content, stale block id, or a non-question block
/// that was bookmarked — are dropped here. This is the single source of truth
/// so the homepage count, the start screen and the quiz all show the SAME
/// number (previously the homepage counted raw card rows while the quiz only
/// played the resolvable ones, e.g. "12" vs "4").
final playablePracticeProvider =
    FutureProvider<({List<ContentBlock> blocks, String? courseId})>((ref) async {
  final queue = await ref.watch(practiceQueueProvider.future);
  if (queue.isEmpty) return (blocks: <ContentBlock>[], courseId: null);

  final db = ref.watch(appDatabaseProvider);
  final blockByCourse = <String, Map<String, ContentBlock>>{};
  final resolved = <ContentBlock>[];
  String? firstCourseId;

  for (final card in queue) {
    var lookup = blockByCourse[card.courseId];
    if (lookup == null) {
      lookup = {};
      // A card's courseId may be either the local primary id (e.g. quiz
      // auto-bookmark passes localCourse.id) or the field course_id (e.g.
      // lesson bookmarks pass widget.course.id = "A2-Rovnice_c1"). Try both
      // so cards aren't silently dropped over an id-scheme mismatch.
      final row = await db.getCourseById(card.courseId) ??
          await db.getCourseByFieldCourseId(card.courseId);
      if (row != null) {
        final data = jsonDecode(row.data) as Map<String, dynamic>;
        final course = Course.fromJsonData(id: row.id, data: data);
        for (final lesson in course.lessons) {
          for (final block in course.getBlocksForLesson(lesson.id)) {
            lookup[block.blockId] = block;
          }
        }
        // Unassigned blocks (present in course `blocks[]` but not referenced by
        // any lesson) are still playable in quizzes and can be bookmarked /
        // auto-bookmarked on a wrong answer, which seeds a practice card. Without
        // them in the lookup those cards resolve to nothing and silently vanish
        // from the queue + count (BR-A2DD22). putIfAbsent so lesson-bound blocks
        // (with their merged default_practice flag) keep priority.
        for (final block in course.getAllBlocks()) {
          lookup.putIfAbsent(block.blockId, () => block);
        }
      }
      blockByCourse[card.courseId] = lookup;
    }

    // Step-level bookmarks store blockId as "baseBlockId:stepId"; fall back to
    // the base block so those cards resolve too.
    var block = lookup[card.blockId];
    if (block == null && card.blockId.contains(':')) {
      block = lookup[card.blockId.split(':').first];
    }
    // Include any resolvable block: answerable blocks (question / v2 steps) are
    // graded automatically, display/content blocks are self-rated in the quiz
    // (Nevím / Připomeň / Jde to / Pamatuji). Only blocks whose course/content
    // can't be resolved at all are dropped.
    if (block != null) {
      resolved.add(block);
      firstCourseId ??= card.courseId;
    }
  }

  return (blocks: resolved, courseId: firstCourseId);
});

/// Count of practice cards the user can actually review now — derived from
/// [playablePracticeProvider] so it matches the quiz exactly.
final dueCardsCountProvider = FutureProvider<int>((ref) async {
  final result = await ref.watch(playablePracticeProvider.future);
  return result.blocks.length;
});
