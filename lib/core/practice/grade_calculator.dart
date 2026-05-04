/// Utility for calculating the FSRS rating grade for an exercise or question block.
class GradeCalculator {
  const GradeCalculator._();

  /// Calculate grade for an exercise/question block.
  ///
  /// Returns an integer in [1, 4] that maps to [fsrs.Rating]:
  ///   1 (Again): wrong answer
  ///   2 (Hard):  correct but used hint or help
  ///   3 (Good):  correct, no help, time > avgTimeSec
  ///   4 (Easy):  correct, no help, time <= avgTimeSec
  static int gradeExercise({
    required bool isCorrect,
    required bool usedHint,
    required bool usedHelp,
    required int responseTimeSec,
    required int avgTimeSec,
  }) {
    if (!isCorrect) return 1;
    if (usedHint || usedHelp) return 2;
    if (responseTimeSec > avgTimeSec) return 3;
    return 4;
  }
}
