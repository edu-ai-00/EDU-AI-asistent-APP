import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';

const _uuid = Uuid();

/// Converts between the app's Drift models and the [fsrs] package types.
class FsrsBridge {
  const FsrsBridge._();

  // ---------------------------------------------------------------------------
  // State mapping
  // ---------------------------------------------------------------------------

  /// Maps the app's integer state (stored in DB) to [fsrs.State].
  ///
  /// DB convention:
  ///   0 = new (never reviewed) → treated as [fsrs.State.learning] step 0
  ///   1 = learning             → [fsrs.State.learning]
  ///   2 = review               → [fsrs.State.review]
  ///   3 = relearning           → [fsrs.State.relearning]
  static fsrs.State _toFsrsState(int state) {
    switch (state) {
      case 0:
      case 1:
        return fsrs.State.learning;
      case 2:
        return fsrs.State.review;
      case 3:
        return fsrs.State.relearning;
      default:
        return fsrs.State.learning;
    }
  }

  /// Maps [fsrs.State] back to the app's integer DB convention.
  static int _fromFsrsState(fsrs.State state) {
    switch (state) {
      case fsrs.State.learning:
        return 1;
      case fsrs.State.review:
        return 2;
      case fsrs.State.relearning:
        return 3;
    }
  }

  // ---------------------------------------------------------------------------
  // Rating mapping
  // ---------------------------------------------------------------------------

  /// Maps a 1-4 grade (from [GradeCalculator]) to [fsrs.Rating].
  static fsrs.Rating toFsrsRating(int rating) {
    switch (rating) {
      case 1:
        return fsrs.Rating.again;
      case 2:
        return fsrs.Rating.hard;
      case 3:
        return fsrs.Rating.good;
      case 4:
        return fsrs.Rating.easy;
      default:
        throw ArgumentError('Invalid rating $rating; expected 1-4.');
    }
  }

  // ---------------------------------------------------------------------------
  // Card conversion
  // ---------------------------------------------------------------------------

  /// Converts a [PracticeCardsTableData] row to an [fsrs.Card] ready for scheduling.
  static fsrs.Card toFsrsCard(PracticeCardsTableData card) {
    final state = _toFsrsState(card.state);

    // Use the card's local UUID hash as a stable integer id for fsrs.Card.
    // fsrs only uses cardId for logging — it doesn't affect scheduling.
    final cardIdInt = card.id.hashCode.abs();

    return fsrs.Card(
      cardId: cardIdInt,
      state: state,
      stability: card.stability > 0 ? card.stability : null,
      difficulty: card.difficulty > 0 ? card.difficulty : null,
      due: card.dueDate.toUtc(),
      lastReview: card.lastReview?.toUtc(),
      // step is set to 0 for new/learning cards; fsrs.Card constructor handles
      // the default (step = 0) when state == State.learning and step == null.
    );
  }

  /// Converts a reviewed [fsrs.Card] back to a [PracticeCardsTableCompanion]
  /// with all updated FSRS fields and [syncStatus] = 1 (pending sync).
  static PracticeCardsTableCompanion fromFsrsCard(
    fsrs.Card fsrsCard,
    String cardId, {
    required int previousReps,
    required int previousLapses,
    required int rating,
  }) {
    final newState = _fromFsrsState(fsrsCard.state);
    final isAgain = rating == 1;

    // Calculate elapsed days from lastReview to now
    final now = DateTime.now();
    final elapsedDays = fsrsCard.lastReview != null
        ? now.difference(fsrsCard.lastReview!).inDays
        : 0;

    // Calculate scheduled days (interval from lastReview to due)
    final scheduledDays = fsrsCard.lastReview != null
        ? fsrsCard.due.difference(fsrsCard.lastReview!).inDays
        : 0;

    return PracticeCardsTableCompanion(
      id: Value(cardId),
      state: Value(newState),
      dueDate: Value(fsrsCard.due.toLocal()),
      stability: Value(fsrsCard.stability ?? 0.0),
      difficulty: Value(fsrsCard.difficulty ?? 0.0),
      reps: Value(previousReps + 1),
      lapses: Value(isAgain ? previousLapses + 1 : previousLapses),
      scheduledDays: Value(scheduledDays),
      elapsedDays: Value(elapsedDays),
      lastReview: Value(fsrsCard.lastReview?.toLocal()),
      syncStatus: const Value(1),
      updatedAt: Value(now),
    );
  }

  // ---------------------------------------------------------------------------
  // Review log builder
  // ---------------------------------------------------------------------------

  /// Builds a [ReviewLogsTableCompanion] from review results.
  static ReviewLogsTableCompanion buildReviewLog({
    required String cardId,
    required String userId,
    required int rating,
    required DateTime shownAt,
    required DateTime reviewedAt,
    required int responseTimeSec,
    required int repetitionNumber,
    required double stabilityAfter,
    required double difficultyAfter,
    required DateTime nextDueDate,
    required int intervalDays,
    String? userFeedback,
  }) {
    return ReviewLogsTableCompanion(
      id: Value(_uuid.v4()),
      cardId: Value(cardId),
      userId: Value(userId),
      rating: Value(rating),
      shownAt: Value(shownAt),
      reviewedAt: Value(reviewedAt),
      responseTimeSec: Value(responseTimeSec),
      repetitionNumber: Value(repetitionNumber),
      stabilityAfter: Value(stabilityAfter),
      difficultyAfter: Value(difficultyAfter),
      nextDueDate: Value(nextDueDate),
      intervalDays: Value(intervalDays),
      userFeedback: Value(userFeedback),
      syncStatus: const Value(1),
      createdAt: Value(DateTime.now()),
    );
  }

  // ---------------------------------------------------------------------------
  // Scheduler builder
  // ---------------------------------------------------------------------------

  /// Builds an [fsrs.Scheduler] from a [StudentFsrsProfilesTableData] profile,
  /// falling back to defaults when the profile is null.
  static fsrs.Scheduler buildScheduler(
      StudentFsrsProfilesTableData? profile) {
    if (profile == null) {
      return fsrs.Scheduler();
    }

    final learningSteps = _parseDurationList(profile.learningSteps);
    final relearningSteps = _parseDurationList(profile.relearningSteps);
    final parameters = _parseWeights(profile.fsrsWeights);

    return fsrs.Scheduler(
      parameters: parameters,
      desiredRetention: profile.desiredRetention,
      learningSteps: learningSteps,
      relearningSteps: relearningSteps,
      maximumInterval: profile.maximumInterval,
      enableFuzzing: profile.enableFuzz,
    );
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Parses a JSON duration list like `["1m","10m"]` into [List<Duration>].
  /// Supports "Xm" (minutes) and "Xd" (days) suffixes.
  static List<Duration> _parseDurationList(String json) {
    try {
      final list = jsonDecode(json) as List<dynamic>;
      return list.map((e) {
        final s = e as String;
        if (s.endsWith('m')) {
          return Duration(minutes: int.parse(s.replaceAll('m', '')));
        } else if (s.endsWith('d')) {
          return Duration(days: int.parse(s.replaceAll('d', '')));
        }
        // fallback: treat as seconds
        return Duration(seconds: int.parse(s));
      }).toList();
    } catch (_) {
      // Return sensible defaults on parse failure
      return const [Duration(minutes: 1), Duration(minutes: 10)];
    }
  }

  /// Parses FSRS weight JSON array, or returns [fsrs.defaultParameters] for
  /// the literal string "default" or on any parse error.
  static List<double> _parseWeights(String raw) {
    if (raw == 'default') return List<double>.from(fsrs.defaultParameters);
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => (e as num).toDouble()).toList();
    } catch (_) {
      return List<double>.from(fsrs.defaultParameters);
    }
  }
}
