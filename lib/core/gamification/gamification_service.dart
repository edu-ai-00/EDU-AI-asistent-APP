/// Pure business-logic service for XP and trophy calculations.
///
/// No Flutter or DB dependencies — all methods are pure functions
/// that can be unit tested in isolation.
///
/// XP rules:
/// - Display bubble (text/image/video step): +1 XP each
/// - Exercise step (correct without hints): +8 XP
/// - Exercise step (otherwise): +5 XP
/// - Course hard cap: total XP from a course cannot exceed [courseMaxXp]
/// - Daily soft cap: first 100 XP at 100%, then 20% rate
class GamificationService {
  const GamificationService();

  /// XP for reading a display bubble.
  static const int bubbleXp = 1;

  /// XP for answering an exercise correctly without hints.
  static const int exerciseCorrectXp = 8;

  /// XP for answering an exercise (with hints or incorrectly).
  static const int exerciseBaseXp = 5;

  /// Daily XP threshold before the soft cap kicks in.
  static const int dailySoftCapThreshold = 100;

  /// Rate of XP earned after exceeding the daily soft cap.
  static const double dailySoftCapRate = 0.20;

  /// XP required per level.
  static const int xpPerLevel = 500;

  /// Calculate raw XP for a completed block based on its steps.
  ///
  /// [displayStepCount] — number of text/image/video (non-evaluation) steps.
  /// [exerciseResults] — list of (isCorrectNoHints) for each evaluation step.
  static int calculateBlockRawXp({
    required int displayStepCount,
    required List<bool> exerciseResults,
  }) {
    int xp = displayStepCount * bubbleXp;
    for (final isCorrectNoHints in exerciseResults) {
      xp += isCorrectNoHints ? exerciseCorrectXp : exerciseBaseXp;
    }
    return xp;
  }

  /// Apply the course hard cap, then daily soft cap, returning effective XP.
  ///
  /// Cap order:
  /// 1. Course hard cap: remaining = [courseMaxXp] - [courseXpEarned]
  /// 2. Clamp raw to remaining
  /// 3. Daily soft cap: split at 100 boundary
  static int applyAllCaps({
    required int rawXp,
    required int courseXpEarned,
    int? courseMaxXp,
    required int dailyXpSoFar,
  }) {
    if (rawXp <= 0) return 0;

    // 1. Course hard cap
    int effective = rawXp;
    if (courseMaxXp != null && courseMaxXp > 0) {
      final remaining = courseMaxXp - courseXpEarned;
      if (remaining <= 0) return 0;
      effective = effective.clamp(0, remaining);
    }

    // 2. Daily soft cap
    effective = applyDailyCap(effective, dailyXpSoFar);

    return effective;
  }

  /// Apply the daily soft cap: first 100 XP at 100%, then 20%.
  ///
  /// Example: dailyXpSoFar=80, rawXp=40
  ///   → 20 at 100% + 20 at 20% = 20 + 4 = 24
  static int applyDailyCap(int rawXp, int dailyXpSoFar) {
    if (rawXp <= 0) return 0;

    if (dailyXpSoFar >= dailySoftCapThreshold) {
      // Already past threshold — all at reduced rate
      return (rawXp * dailySoftCapRate).round();
    }

    final roomAtFullRate = dailySoftCapThreshold - dailyXpSoFar;
    if (rawXp <= roomAtFullRate) {
      // All fits within full rate
      return rawXp;
    }

    // Split: some at full rate, rest at reduced rate
    final atFullRate = roomAtFullRate;
    final remainder = rawXp - roomAtFullRate;
    final atReducedRate = (remainder * dailySoftCapRate).round();
    return atFullRate + atReducedRate;
  }

  /// Calculate level from total XP.
  static int calculateLevel(int totalXp) {
    return (totalXp ~/ xpPerLevel) + 1;
  }
}
