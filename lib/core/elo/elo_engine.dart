// Bidirectional ELO engine for adaptive learning.
//
// Adjusts both the student's proficiency rating and the task's difficulty
// rating after each interaction. Uses 35 GPF subconstructs (N1.1–A3.4).
//
// This is a pure Dart class with no Flutter dependencies so it can be
// unit-tested without a Flutter environment.
import 'dart:math';

/// Number of GPF subconstructs.
const int kGpfDimensions = 35;

/// Default student rating used when no prior data exists.
const double kDefaultStudentRating = 6.0;

// ─── Algorithm constants ─────────────────────────────────────────────────────

/// Sigmoid steepness.
const double kLambda = 0.5;

/// Base K-factor for student updates.
const double kK0 = 1.0;

/// Student K-factor decay rate.
const double kAlpha = 0.1;

/// Base K-factor for task (item) updates.
const double kK0Item = 0.01;

/// Task K-factor decay rate.
const double kAlphaItem = 0.01;

/// Bias added to student rating when computing expected score for the task.
const double kBiasForItem = 1.0;

// ─── Result class ────────────────────────────────────────────────────────────

/// Result of a single bidirectional ELO update.
class EloUpdateResult {
  /// Updated student ELO profile (35 elements, nullable per subconstruct).
  final List<double?> profilElo;

  /// Updated student task-count vector (35 elements).
  final List<int> profilPocet;

  /// Updated task ELO vector (35 elements, nullable per subconstruct).
  final List<double?> eloVector;

  /// Updated global task solve-count vector (35 elements).
  final List<int> itemPocet;

  /// Indices of subconstructs that were actually updated.
  final List<int> updatedIndices;

  const EloUpdateResult({
    required this.profilElo,
    required this.profilPocet,
    required this.eloVector,
    required this.itemPocet,
    required this.updatedIndices,
  });
}

// ─── Task selection ──────────────────────────────────────────────────────────

/// A candidate task for adaptive selection.
class TaskCandidate {
  final String blockId;
  final List<double> relationVector;
  final List<double?> eloVector;

  const TaskCandidate({
    required this.blockId,
    required this.relationVector,
    required this.eloVector,
  });
}

// ─── Engine ──────────────────────────────────────────────────────────────────

/// Pure-Dart bidirectional ELO engine.
///
/// All methods are static — no instance state is needed.
class EloEngine {
  const EloEngine._();

  /// Standard sigmoid function.
  static double sigmoid(double x) {
    return 1.0 / (1.0 + exp(-x));
  }

  /// Perform a bidirectional ELO update for a single task interaction.
  ///
  /// [profilElo]       – student's current ELO ratings (35, nullable).
  /// [profilPocet]     – how many tasks the student has solved per subconstruct.
  /// [relationVector]  – block's relation vector (35, values 0/1/2).
  /// [eloVector]       – block's current ELO difficulty (35, nullable).
  /// [itemPocet]       – global solve-count vector for this block.
  /// [score]           – interaction outcome: 0.0, 0.5, 0.75, or 1.0.
  ///
  /// Returns an [EloUpdateResult] with updated copies of all four vectors
  /// plus a list of which subconstruct indices were modified.
  static EloUpdateResult updateTask({
    required List<double?> profilElo,
    required List<int> profilPocet,
    required List<double> relationVector,
    required List<double?> eloVector,
    required List<int> itemPocet,
    required double score,
  }) {
    // Work on mutable copies so callers keep their originals.
    final newProfilElo = List<double?>.from(profilElo);
    final newProfilPocet = List<int>.from(profilPocet);
    final newEloVector = List<double?>.from(eloVector);
    final newItemPocet = List<int>.from(itemPocet);
    final updatedIndices = <int>[];

    final length = min(kGpfDimensions, relationVector.length);

    for (int k = 0; k < length; k++) {
      // Only process subconstructs with strong relation AND valid task ELO.
      if (relationVector[k] <= 1) continue;
      if (k >= eloVector.length || eloVector[k] == null || eloVector[k]! <= 0) {
        continue;
      }

      final double d = eloVector[k]!; // task difficulty
      final double? r = newProfilElo[k]; // student rating (may be null)

      // ── First-contact handling ──
      // On first contact, only set initial rating — skip student & task update.
      // Uses delta=0 (expected=0.5): win → set to task difficulty, lose → 6.0.
      if (r == null || r.isNaN) {
        final expected = sigmoid(kLambda * 0.0); // 0.5
        if (score >= expected) {
          newProfilElo[k] = d;
        } else {
          newProfilElo[k] = kDefaultStudentRating;
        }
        updatedIndices.add(k);
        continue;
      }

      // ── Student update ──
      final delta = r - d;
      final expected = sigmoid(kLambda * delta);
      final kStudent = kK0 / (1 + kAlpha * newProfilPocet[k]);
      final studentDiff = kStudent * (score - expected);
      final newR = (r + studentDiff).clamp(0.0, 10.0);

      // ── Task update (with bias) ──
      final biasedDelta = (r + kBiasForItem) - d;
      final expectedBiased = sigmoid(kLambda * biasedDelta);
      final kTask = kK0Item / (1 + kAlphaItem * newItemPocet[k]);
      final taskDiff = -kTask * (score - expectedBiased);
      final newD = (d + taskDiff).clamp(0.0, 10.0);

      // ── Apply ──
      newProfilElo[k] = newR;
      newProfilPocet[k] += 1;
      newEloVector[k] = newD;
      newItemPocet[k] += 1;

      updatedIndices.add(k);
    }

    return EloUpdateResult(
      profilElo: newProfilElo,
      profilPocet: newProfilPocet,
      eloVector: newEloVector,
      itemPocet: newItemPocet,
      updatedIndices: updatedIndices,
    );
  }

  /// Select the best-matching task from a pool of [candidates].
  ///
  /// Returns the index of the candidate whose ELO vector is closest to the
  /// student's current profile, or `null` if no valid candidate exists.
  ///
  /// Distance metric: sum of squared differences across all active
  /// subconstructs (relation_vector[k] > 1 and elo_vector[k] != null).
  static int? selectTask({
    required List<double?> profilElo,
    required List<TaskCandidate> candidates,
  }) {
    if (candidates.isEmpty) return null;

    int? bestIndex;
    double bestNorm = double.infinity;

    for (int i = 0; i < candidates.length; i++) {
      final candidate = candidates[i];
      double norm = 0.0;
      bool hasActive = false;

      final length = min(kGpfDimensions, candidate.relationVector.length);
      for (int k = 0; k < length; k++) {
        if (candidate.relationVector[k] <= 1) continue;
        if (k >= candidate.eloVector.length || candidate.eloVector[k] == null) {
          continue;
        }

        hasActive = true;
        final studentRating = (k < profilElo.length ? profilElo[k] : null)
            ?? kDefaultStudentRating;
        final diff = candidate.eloVector[k]! - studentRating;
        norm += diff * diff;
      }

      if (hasActive && norm < bestNorm) {
        bestNorm = norm;
        bestIndex = i;
      }
    }

    return bestIndex;
  }
}
