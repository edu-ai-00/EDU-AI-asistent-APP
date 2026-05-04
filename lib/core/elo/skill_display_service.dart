// Computes displayable skill cards from a user's ELO profile.
//
// Ties together ConfidenceCalculator (domain-level summaries) and
// GpfStructure (domain definitions) to produce SkillDisplay objects
// ready for rendering in the UI.
//
// This is a pure Dart class with no Flutter dependencies.
import 'confidence_calculator.dart';
import 'gpf_structure.dart';
import '../../models/skill_display_model.dart';

class SkillDisplayService {
  /// Compute a [SkillDisplay] list from a user's ELO profile.
  ///
  /// [profilElo] – full 35-element student ELO profile (nullable per dim).
  /// [profilPocet] – full 35-element interaction counts.
  /// [minCount] – minimum interactions for a dimension to be eligible.
  /// [c] – half-width scaling constant for the confidence interval.
  /// [category] – display category label (e.g. "Matematika").
  static List<SkillDisplay> computeSkills({
    required List<double?> profilElo,
    required List<int> profilPocet,
    int minCount = 10,
    double c = 2.5,
    String category = 'Matematika',
  }) {
    final skills = <SkillDisplay>[];

    for (final domain in GpfStructure.domains) {
      final summary = ConfidenceCalculator.computeDomainSummary(
        profilElo: profilElo,
        profilPocet: profilPocet,
        dimensionIndices: domain.indices,
        minCount: minCount,
        c: c,
        domainCode: domain.code,
        domainName: domain.name,
      );

      if (summary.meanElo == null) {
        // Not enough data — show card with message.
        skills.add(SkillDisplay(
          id: domain.code,
          name: domain.name,
          category: category,
          emoji: domain.emoji,
          level: 0,
          confidenceLow: 0,
          confidenceHigh: 0,
          difficulty: 'beginner',
          message: summary.message,
        ));
      } else {
        final level = summary.meanElo!.clamp(1.0, 10.0);

        skills.add(SkillDisplay(
          id: domain.code,
          name: domain.name,
          category: category,
          emoji: domain.emoji,
          level: level,
          confidenceLow: summary.intervalLow!.round(),
          confidenceHigh: summary.intervalHigh!.round(),
          difficulty: _difficultyFromLevel(level),
        ));
      }
    }

    return skills;
  }

  /// Maps a numeric level (1–10) to a difficulty label.
  static String _difficultyFromLevel(double level) {
    if (level <= 3) return 'beginner';
    if (level <= 7) return 'intermediate';
    return 'expert';
  }
}
