/// Display-only model for rendering skill cards in the UI.
///
/// Computed from the user's ELO profile via [SkillDisplayService].
/// When data is insufficient, [level] is 0 and [message] is set.
class SkillDisplay {
  final String id;
  final String name;
  final String category; // e.g. "Matematika"
  final String emoji;
  final double level; // 0.0 (no data) or 1.0–10.0
  final int confidenceLow;
  final int confidenceHigh;
  final String difficulty; // beginner / intermediate / expert

  /// Informational message when there is not enough data.
  /// Null when the skill has real computed values.
  final String? message;

  /// Whether this skill has enough data to display meaningful values.
  bool get hasData => level > 0 && message == null;

  const SkillDisplay({
    required this.id,
    required this.name,
    required this.category,
    required this.emoji,
    required this.level,
    required this.confidenceLow,
    required this.confidenceHigh,
    required this.difficulty,
    this.message,
  });
}
