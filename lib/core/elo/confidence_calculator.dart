// Confidence interval calculator for domain-level ELO summaries.
//
// Computes a mean ELO and confidence interval for each GPF domain by
// aggregating the individual subconstruct (dimension) ratings that belong
// to that domain. Dimensions without enough interactions are excluded.
//
// This is a pure Dart class with no Flutter dependencies so it can be
// unit-tested without a Flutter environment.
import 'dart:math';

// ─── Domain summary ─────────────────────────────────────────────────────────

/// Aggregated ELO summary for a single GPF domain.
class DomainSummary {
  /// Short domain code, e.g. "N".
  final String domainCode;

  /// Human-readable domain name, e.g. "Číslo a operace".
  final String domainName;

  /// Average ELO across eligible dimensions, or null if insufficient data.
  final double? meanElo;

  /// Lower bound of the confidence interval (clamped to 0, rounded to 2 dp).
  final double? intervalLow;

  /// Upper bound of the confidence interval (clamped to 10, rounded to 2 dp).
  final double? intervalHigh;

  /// Czech confidence label: "nižší" / "střední" / "vyšší", or null.
  final String? confidenceLabel;

  /// Number of dimensions that had enough data to be included.
  final int includedCount;

  /// Number of dimensions that were excluded due to insufficient data.
  final int excludedCount;

  /// Median interaction count across eligible dimensions.
  final double? medianCount;

  /// Informational message when the domain has no usable data.
  /// Null when there is enough data to compute a summary.
  final String? message;

  const DomainSummary({
    required this.domainCode,
    required this.domainName,
    this.meanElo,
    this.intervalLow,
    this.intervalHigh,
    this.confidenceLabel,
    required this.includedCount,
    required this.excludedCount,
    this.medianCount,
    this.message,
  });
}

// ─── Calculator ─────────────────────────────────────────────────────────────

/// Computes confidence intervals for domain-level ELO summaries.
class ConfidenceCalculator {
  /// Message returned when a domain has no eligible dimensions.
  static const String _insufficientDataMessage =
      'Na odhad v této oblasti zatím nemáme dost údajů.';

  /// Computes a [DomainSummary] for a single GPF domain.
  ///
  /// [profilElo] – full 35-element student ELO profile (nullable per dim).
  /// [profilPocet] – full 35-element interaction counts.
  /// [dimensionIndices] – indices into the profile that belong to this domain.
  /// [minCount] – minimum interactions required for a dimension to be eligible.
  /// [c] – half-width scaling constant for the confidence interval.
  /// [domainCode] – short code for the domain (e.g. "N").
  /// [domainName] – human-readable name (e.g. "Číslo a operace").
  static DomainSummary computeDomainSummary({
    required List<double?> profilElo,
    required List<int> profilPocet,
    required List<int> dimensionIndices,
    int minCount = 10,
    double c = 2.5,
    String domainCode = '',
    String domainName = '',
  }) {
    // Filter eligible dimensions.
    final eligibleElo = <double>[];
    final eligibleCounts = <int>[];

    for (final i in dimensionIndices) {
      final elo = profilElo[i];
      final count = profilPocet[i];
      // Include any dimension with a real ELO value (minCount only affects
      // the confidence label, not eligibility).
      if (elo != null && elo != 0) {
        eligibleElo.add(elo);
        eligibleCounts.add(count);
      }
    }

    final includedCount = eligibleElo.length;
    final excludedCount = dimensionIndices.length - includedCount;

    // Not enough data — return empty summary with message.
    if (includedCount == 0) {
      return DomainSummary(
        domainCode: domainCode,
        domainName: domainName,
        includedCount: 0,
        excludedCount: excludedCount,
        message: _insufficientDataMessage,
      );
    }

    // Mean ELO — simple average.
    final mean = eligibleElo.reduce((a, b) => a + b) / includedCount;

    // Median interaction count.
    final median = _medianInt(eligibleCounts);

    // Confidence interval half-width (guard against 0 count).
    final halfWidth = median > 0 ? c / sqrt(median) : 0.0;
    final low = max(0.0, mean - halfWidth);
    final high = min(10.0, mean + halfWidth);

    return DomainSummary(
      domainCode: domainCode,
      domainName: domainName,
      meanElo: _round2(mean),
      intervalLow: _round2(low),
      intervalHigh: _round2(high),
      confidenceLabel: confidenceLabel(median),
      includedCount: includedCount,
      excludedCount: excludedCount,
      medianCount: median,
    );
  }

  /// Returns a Czech confidence label based on median interaction count.
  ///
  /// - 30+   → "vyšší"
  /// - 20–29 → "střední"
  /// - 5–19  → "nižší"
  /// - <5    → "velmi nízká"
  /// - null  → null
  static String? confidenceLabel(double? medianCount) {
    if (medianCount == null) return null;
    if (medianCount >= 30) return 'vyšší';
    if (medianCount >= 20) return 'střední';
    if (medianCount >= 5) return 'nižší';
    return 'velmi nízká';
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  /// Computes the median of a non-empty list of integers.
  ///
  /// Returns the result as a double (average of two middle values when the
  /// list length is even).
  static double _medianInt(List<int> values) {
    assert(values.isNotEmpty, 'Cannot compute median of an empty list');
    final sorted = List<int>.from(values)..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) {
      return sorted[mid].toDouble();
    }
    return (sorted[mid - 1] + sorted[mid]) / 2.0;
  }

  /// Rounds [value] to 2 decimal places.
  static double _round2(double value) {
    return (value * 100).roundToDouble() / 100;
  }
}
