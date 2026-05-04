import '../database/app_database.dart';

/// Builds the daily practice queue from a student's cards.
///
/// Pure function — no database access, no side effects.
class QueueBuilder {
  const QueueBuilder._();

  /// Builds an ordered, capped list of cards to review today.
  ///
  /// Algorithm:
  ///   1. Partition cards into: overdue (state > 0, due <= now), new (state == 0).
  ///      All other cards (state > 0 but not yet due) are excluded.
  ///   2. Sort overdue by weight DESC then dueDate ASC (most-important / longest-overdue first).
  ///   3. Sort new by weight DESC; take up to [dailyNewLimit].
  ///   4. Merge: overdue first, then new.
  ///   5. Diversify courses (interleave cards from different courses within same weight bucket).
  ///   6. Cap at ([dailyReviewLimit] - [todayReviewCount]).
  ///   7. Return [] if no remaining slots.
  static List<PracticeCardsTableData> buildQueue({
    required List<PracticeCardsTableData> allCards,
    required int dailyNewLimit,
    required int dailyReviewLimit,
    int todayReviewCount = 0,
  }) {
    final remainingSlots = dailyReviewLimit - todayReviewCount;
    if (remainingSlots <= 0) return [];

    final now = DateTime.now();

    // 1. Partition
    final overdue = <PracticeCardsTableData>[];
    final newCards = <PracticeCardsTableData>[];

    for (final card in allCards) {
      if (!card.isActive) continue;
      if (card.state == 0) {
        newCards.add(card);
      } else if (card.dueDate.isBefore(now) || card.dueDate.isAtSameMomentAs(now)) {
        overdue.add(card);
      }
      // cards not yet due are ignored
    }

    // 2. Sort overdue: weight DESC, dueDate ASC
    overdue.sort((a, b) {
      final weightCmp = b.weight.compareTo(a.weight);
      if (weightCmp != 0) return weightCmp;
      return a.dueDate.compareTo(b.dueDate);
    });

    // 3. Sort new: weight DESC; cap at dailyNewLimit
    newCards.sort((a, b) => b.weight.compareTo(a.weight));
    final cappedNew = newCards.take(dailyNewLimit).toList();

    // 4. Merge
    final merged = [...overdue, ...cappedNew];

    // 5. Diversify courses
    final diversified = _diversifyCourses(merged);

    // 6. Cap
    return diversified.take(remainingSlots).toList();
  }

  /// Interleaves cards from different courses within the same weight bucket to
  /// provide variety during a session.
  ///
  /// Cards are grouped into weight buckets (rounded to 1 decimal place).
  /// Within each bucket, cards are interleaved round-robin by courseId so that
  /// no single course dominates consecutive positions.
  static List<PracticeCardsTableData> _diversifyCourses(
      List<PracticeCardsTableData> cards) {
    if (cards.isEmpty) return cards;

    // Group into weight buckets while preserving within-bucket order.
    final buckets = <double, List<PracticeCardsTableData>>{};
    final bucketOrder = <double>[];

    for (final card in cards) {
      // Round weight to 1 dp for bucketing (e.g. 5.0, 4.5, …)
      final bucket = (card.weight * 10).roundToDouble() / 10;
      if (!buckets.containsKey(bucket)) {
        buckets[bucket] = [];
        bucketOrder.add(bucket);
      }
      buckets[bucket]!.add(card);
    }

    final result = <PracticeCardsTableData>[];

    for (final bucket in bucketOrder) {
      final bucketCards = buckets[bucket]!;

      // Group by courseId within the bucket
      final byCourse = <String, List<PracticeCardsTableData>>{};
      final courseOrder = <String>[];
      for (final card in bucketCards) {
        if (!byCourse.containsKey(card.courseId)) {
          byCourse[card.courseId] = [];
          courseOrder.add(card.courseId);
        }
        byCourse[card.courseId]!.add(card);
      }

      // Interleave round-robin
      int maxLen = byCourse.values.fold(0, (m, l) => m > l.length ? m : l.length);
      for (int i = 0; i < maxLen; i++) {
        for (final courseId in courseOrder) {
          final list = byCourse[courseId]!;
          if (i < list.length) {
            result.add(list[i]);
          }
        }
      }
    }

    return result;
  }
}
