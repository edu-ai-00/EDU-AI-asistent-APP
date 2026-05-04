import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../models/block_model.dart';

const _uuid = Uuid();

/// Repository for practice cards, review logs, and FSRS profiles.
/// Wraps AppDatabase CRUD methods and adds higher-level operations.
class PracticeRepository {
  final AppDatabase _db;

  PracticeRepository({required AppDatabase db}) : _db = db;

  // ═══════════════════════════════════════════════════════════════════════════
  // Practice Card Methods
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get all active practice cards for a user.
  Future<List<PracticeCardsTableData>> getActiveCards(String userId) {
    return _db.getActivePracticeCards(userId);
  }

  /// Get due practice cards for a user (dueDate <= now).
  Future<List<PracticeCardsTableData>> getDueCards(String userId) {
    return _db.getDuePracticeCards(userId);
  }

  /// Get new (state=0) practice cards for a user.
  Future<List<PracticeCardsTableData>> getNewCards(String userId, {int limit = 10}) {
    return _db.getNewPracticeCards(userId, limit: limit);
  }

  /// Get a practice card by userId and blockId.
  Future<PracticeCardsTableData?> getCardByBlock(String userId, String blockId) {
    return _db.getPracticeCardByBlock(userId, blockId);
  }

  /// Insert or update a practice card.
  Future<void> updateCard(PracticeCardsTableCompanion card) {
    return _db.upsertPracticeCard(card);
  }

  /// Deactivate a practice card (sets isActive=false, syncStatus=1).
  Future<void> deactivateCard(String cardId) {
    return _db.upsertPracticeCard(PracticeCardsTableCompanion(
      id: Value(cardId),
      isActive: const Value(false),
      syncStatus: const Value(1),
      updatedAt: Value(DateTime.now()),
    ));
  }

  /// Reactivate a practice card (sets isActive=true, syncStatus=1).
  Future<void> reactivateCard(String cardId) {
    return _db.upsertPracticeCard(PracticeCardsTableCompanion(
      id: Value(cardId),
      isActive: const Value(true),
      syncStatus: const Value(1),
      updatedAt: Value(DateTime.now()),
    ));
  }

  /// Count due practice cards for a user.
  Future<int> countDueCards(String userId) {
    return _db.countDuePracticeCards(userId);
  }

  /// Get practice cards that need syncing to the server.
  Future<List<PracticeCardsTableData>> getPendingSyncCards() {
    return _db.getPendingSyncPracticeCards();
  }

  /// Create a practice card from a content block.
  ///
  /// - If the card already exists and is active, returns null (no-op).
  /// - If the card already exists but is inactive and [sourceType] == 'bookmark',
  ///   reactivates it and returns the updated card.
  /// - Otherwise, creates a new card seeded with FSRS data from [block.fsrs] if present.
  Future<PracticeCardsTableData?> createCardFromBlock({
    required String userId,
    required String courseId,
    required String lessonId,
    required ContentBlock block,
    required String sourceType,
  }) async {
    final existing = await _db.getPracticeCardByBlock(userId, block.blockId);

    if (existing != null) {
      if (existing.isActive) {
        // Already exists and is active — no-op
        return null;
      }
      // Inactive card: reactivate if triggered by bookmark
      if (sourceType == 'bookmark') {
        await reactivateCard(existing.id);
        return _db.getPracticeCardByBlock(userId, block.blockId);
      }
      return null;
    }

    // Create a new card
    final now = DateTime.now();
    final cardId = _uuid.v4();
    final fsrs = block.fsrs;

    final companion = PracticeCardsTableCompanion(
      id: Value(cardId),
      userId: Value(userId),
      courseId: Value(courseId),
      lessonId: Value(lessonId),
      blockId: Value(block.blockId),
      sourceType: Value(sourceType),
      state: const Value(0),
      dueDate: Value(fsrs?.dueDate?.toUtc() ?? now.toUtc()),
      stability: Value(fsrs?.stability ?? 0.0),
      difficulty: Value(fsrs?.difficulty ?? 0.0),
      reps: Value(fsrs?.reps ?? 0),
      lapses: Value(fsrs?.lapses ?? 0),
      scheduledDays: const Value(0),
      elapsedDays: const Value(0),
      lastReview: Value(fsrs?.lastReview),
      isActive: const Value(true),
      syncStatus: const Value(1),
      createdAt: Value(now),
      updatedAt: Value(now),
    );

    await _db.upsertPracticeCard(companion);
    return _db.getPracticeCardByBlock(userId, block.blockId);
  }

  /// Create practice cards from all blocks in a lesson that have defaultPractice=true.
  ///
  /// Returns the count of newly created cards.
  Future<int> createCardsFromLesson({
    required String userId,
    required String courseId,
    required String lessonId,
    required List<ContentBlock> blocks,
  }) async {
    int created = 0;
    for (final block in blocks) {
      if (!block.defaultPractice) continue;
      final card = await createCardFromBlock(
        userId: userId,
        courseId: courseId,
        lessonId: lessonId,
        block: block,
        sourceType: 'lesson',
      );
      if (card != null) created++;
    }
    return created;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Review Log Methods
  // ═══════════════════════════════════════════════════════════════════════════

  /// Insert a review log entry.
  Future<void> insertReviewLog(ReviewLogsTableCompanion log) {
    return _db.insertReviewLog(log);
  }

  /// Get all review logs for a card.
  Future<List<ReviewLogsTableData>> getLogsForCard(String cardId) {
    return _db.getReviewLogsForCard(cardId);
  }

  /// Count reviews done today for a user.
  Future<int> getTodayReviewCount(String userId) {
    return _db.getTodayReviewCount(userId);
  }

  /// Get review logs that need syncing.
  Future<List<ReviewLogsTableData>> getPendingSyncLogs() {
    return _db.getPendingSyncReviewLogs();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FSRS Profile Methods
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get the FSRS profile for a user.
  Future<StudentFsrsProfilesTableData?> getFsrsProfile(String userId) {
    return _db.getFsrsProfile(userId);
  }

  /// Insert or update a student FSRS profile.
  Future<void> saveFsrsProfile(StudentFsrsProfilesTableCompanion profile) {
    return _db.upsertFsrsProfile(profile);
  }
}
