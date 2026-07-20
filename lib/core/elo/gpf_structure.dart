/// Static GPF (General Proficiency Framework) structure for the math vector.
///
/// Defines the 5 domain groupings that partition the 35-dimension ELO profile
/// vector. This holds only the structural, non-label data the backend does not
/// provide: the domain code, its emoji, and which vector indices belong to it.
///
/// Human-readable **labels** (domain / construct / subconstruct names) are NOT
/// hardcoded here — they are the backend's canonical Czech vector labeling,
/// fetched via `GpfLabelRepository` (see BR-N2E9MF). Look up a domain's Czech
/// name by its [GpfDomain.code].
library;

/// A top-level domain grouping in the GPF framework.
class GpfDomain {
  /// Short code identifying the domain (e.g. "N", "M", "G"). Used to resolve
  /// the Czech display name from the backend label set.
  final String code;

  /// Emoji representing the domain (Unicode). Backend has no emoji, so it stays
  /// app-local.
  final String emoji;

  /// Indices of subconstructs belonging to this domain in the 35-dim vector.
  final List<int> indices;

  const GpfDomain({
    required this.code,
    required this.emoji,
    required this.indices,
  });
}

/// Central registry of the GPF structure — domain groupings only.
///
/// The index groupings mirror the backend default GPF formula
/// (`SkillComputationService::defaultGpfFormula`). Labels come from the
/// backend; see [GpfDomain] docs.
class GpfStructure {
  GpfStructure._();

  /// The 5 top-level GPF domains, in display order.
  static const List<GpfDomain> domains = [
    GpfDomain(
      code: 'N',
      emoji: '\u{1F9EE}', // 🧮
      indices: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16],
    ),
    GpfDomain(
      code: 'M',
      emoji: '\u{1F4CF}', // 📏
      indices: [17, 18, 19, 20, 21],
    ),
    GpfDomain(
      code: 'G',
      emoji: '\u{1F4D0}', // 📐
      indices: [22, 23, 24],
    ),
    GpfDomain(
      code: 'S',
      emoji: '\u{1F4CA}', // 📊
      indices: [25, 26, 27, 28],
    ),
    GpfDomain(
      code: 'A',
      emoji: '\u{2696}\u{FE0F}', // ⚖️
      indices: [29, 30, 31, 32, 33, 34],
    ),
  ];

  /// Returns the [GpfDomain] matching [code], or `null` if not found.
  static GpfDomain? domainByCode(String code) {
    for (final domain in domains) {
      if (domain.code == code) return domain;
    }
    return null;
  }
}
