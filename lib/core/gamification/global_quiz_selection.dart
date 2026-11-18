// ELO-aware question selection for the global quiz ("Global Quiz v1").
//
// After the student picks domains/courses in the entry dialog, this narrows
// the candidate pool to questions matched to their ELO profile:
//
//   1. domain filter — keep blocks touching a chosen domain (relation == 2),
//   2. rough band on the averages (relation-2 components only):
//        drop tasks with avg_task < avg_student − 1,
//        and, while more than [limit] remain, avg_task > avg_student + 2,
//   3. hand the rest to the Pilot 2 engine (BR-Y2XNB9):
//      `EloEngine.selectRandomSubsetFromTopCandidates` ranks them by the MEAN
//      squared difference over the relation-2 components
//      (`EloEngine.rankCandidates`) and draws [limit] distinct tasks from the
//      [kGlobalQuizCandidateWindow] nearest.
//
// Steps 1–2 are the application-level filters the engine leaves to its
// caller. Each relaxes itself when it would leave fewer than [limit]
// candidates — the spec's "v případě nedostatku úloh se filtr uvolní/zruší".
// Blocks with no usable GPF vectors cannot be ranked; they serve as fill-up
// when the ranked candidates alone cannot reach [limit].
//
// With several domains chosen, steps 2–3 run once per domain over its own
// share of the ten slots (BR-ZQABZN). Over the undivided pool the ranking is
// blind to domains: whichever domain sits nearest the student's profile can
// fill the whole [kGlobalQuizCandidateWindow] window and hand over a quiz
// from one domain although every box is checked. A domain that cannot fill
// its share leaves the slots to the others, so the quiz still holds ten.
//
// Task difficulty is the effective one the answer path uses (BR-697NCA): the
// server's calibrated value per dimension where the last pull brought one,
// the course content's elo_vector elsewhere.
//
// Pure Dart, no Flutter — unit-tested directly.
library;

import 'dart:math';

import '../../models/block_model.dart';
import '../elo/elo_engine.dart';
import '../elo/gpf_structure.dart';
import '../elo/gpf_vector_shape.dart';
import '../elo/task_difficulty.dart';
import 'global_quiz.dart';

/// How many nearest candidates survive the distance ranking before the random
/// draw ("vezme se nejvýše 20 nejbližších kandidátů").
const int kGlobalQuizCandidateWindow = 20;

/// Rough band below the student's level ("elo_úlohy < elo_žáka - 1").
const double kGlobalQuizEloLowerMargin = 1.0;

/// Rough band above the student's level ("elo_úlohy > elo_žáka + 2").
const double kGlobalQuizEloUpperMargin = 2.0;

bool _isRating(double value) =>
    value.isFinite && value >= 0.0 && value <= 10.0;

/// [block]'s GPF vectors as an engine candidate, or null when it carries none
/// the engine would accept. [calibrated] is the server's calibrated task ELO
/// for the block, if any.
///
/// The engine validates strictly and throws: exactly 35 slots, relation
/// 0/1/2, task ELO 0..10. Length is fitted the way the answer path does it
/// (gpf_vector_shape.dart); a value outside that contract makes the block
/// unrankable instead of throwing out of the quiz start.
TaskCandidate? _taskCandidate(ContentBlock block, [List<double?>? calibrated]) {
  final relation = block.gpf?.relationVector;
  final elo = block.gpf?.eloVector;
  if (relation == null || elo == null) return null;

  final candidate = TaskCandidate(
    blockId: block.blockId,
    relationVector: fitGpfVector([for (final r in relation) r ?? 0.0], 0.0),
    eloVector: effectiveTaskElo(elo, calibrated),
  );
  for (var k = 0; k < kGpfDimensions; k++) {
    final r = candidate.relationVector[k];
    if (r != 0.0 && r != 1.0 && r != 2.0) return null;
    final e = candidate.eloVector[k];
    if (e != null && !_isRating(e)) return null;
  }
  return candidate;
}

/// The dimensions the engine treats as active for [candidate]: relation == 2
/// with a task ELO — the test `EloEngine.candidateDistance` applies.
List<int> _activeIndices(TaskCandidate candidate) => [
      for (var k = 0; k < kGpfDimensions; k++)
        if (candidate.relationVector[k] == 2.0 &&
            candidate.eloVector[k] != null)
          k,
    ];

/// Whether [block] touches [domain] with relation == 2.
bool blockTouchesDomain(ContentBlock block, GpfDomain domain) {
  final candidate = _taskCandidate(block);
  if (candidate == null) return false;
  return _activeIndices(candidate).any(domain.indices.contains);
}

/// Domain codes represented across [pool] — what the entry dialog offers.
Set<String> representedDomains(Iterable<ContentBlock> pool) {
  final codes = <String>{};
  for (final block in pool) {
    for (final domain in GpfStructure.domains) {
      if (codes.contains(domain.code)) continue;
      if (blockTouchesDomain(block, domain)) codes.add(domain.code);
    }
  }
  return codes;
}

/// [studentElo] fitted to the engine's 35 slots; a rating outside its 0..10
/// contract reads as unrated, so the engine's default applies there.
List<double?> _engineProfile(List<double?> studentElo) => [
      for (final value in fitGpfVector(studentElo, null))
        value != null && _isRating(value) ? value : null,
    ];

class _RankableBlock {
  final ContentBlock block;
  final TaskCandidate task;

  /// The engine-active dimensions behind the averages — what decides which
  /// domain's share this block can fill.
  final List<int> active;
  final double taskAvg;
  final double studentAvg;
  const _RankableBlock(
    this.block,
    this.task,
    this.active,
    this.taskAvg,
    this.studentAvg,
  );

  bool touches(GpfDomain domain) => active.any(domain.indices.contains);
}

/// [block] with the averages the rough band compares, or null when the engine
/// could not rank it.
_RankableBlock? _rankable(
  ContentBlock block,
  List<double?> profile,
  List<double?>? calibrated,
) {
  final task = _taskCandidate(block, calibrated);
  if (task == null) return null;
  final active = _activeIndices(task);
  if (active.isEmpty) return null;

  var taskSum = 0.0;
  var studentSum = 0.0;
  for (final k in active) {
    taskSum += task.eloVector[k]!;
    studentSum += profile[k] ?? kDefaultStudentRating;
  }
  return _RankableBlock(
    block,
    task,
    active,
    taskSum / active.length,
    studentSum / active.length,
  );
}

/// Steps 2–3 over [ranked] for a budget of [limit] slots: the rough band,
/// then the engine's draw from the nearest [kGlobalQuizCandidateWindow].
List<ContentBlock> _drawRanked(
  List<_RankableBlock> ranked,
  List<double?> profile,
  int limit,
  Random rng,
) {
  if (limit <= 0 || ranked.isEmpty) return const [];

  var banded = ranked
      .where((r) => r.taskAvg >= r.studentAvg - kGlobalQuizEloLowerMargin)
      .toList();
  if (banded.length < limit) banded = ranked;
  if (banded.length > limit) {
    final capped = banded
        .where((r) => r.taskAvg <= r.studentAvg + kGlobalQuizEloUpperMargin)
        .toList();
    if (capped.length >= limit) banded = capped;
  }

  final picks = EloEngine.selectRandomSubsetFromTopCandidates(
    profilElo: profile,
    candidates: [for (final r in banded) r.task],
    count: limit,
    topN: kGlobalQuizCandidateWindow,
    random: rng,
  );
  return [for (final i in picks) banded[i].block];
}

/// Select up to [limit] blocks from [pool] for the student's [studentElo]
/// profile, restricted to [domainCodes] (empty = no domain restriction).
/// [calibratedTaskElo] maps block id → the server's calibrated task ELO.
List<ContentBlock> selectGlobalQuizBlocks({
  required List<ContentBlock> pool,
  required List<double?> studentElo,
  Set<String> domainCodes = const {},
  Map<String, List<double?>> calibratedTaskElo = const {},
  Random? random,
  int limit = globalQuizLength,
}) {
  final rng = random ?? Random();
  if (limit <= 0) return [];
  if (pool.length <= limit) return List.of(pool);

  final domains = domainCodes
      .map(GpfStructure.domainByCode)
      .whereType<GpfDomain>()
      .toList();

  // 1. Domain filter — relaxed entirely when it starves the pool.
  var candidates = pool;
  if (domains.isNotEmpty) {
    final filtered = pool
        .where((b) => domains.any((d) => blockTouchesDomain(b, d)))
        .toList();
    if (filtered.length >= limit) candidates = filtered;
  }

  final profile = _engineProfile(studentElo);
  final ranked = <_RankableBlock>[];
  final unrankable = <ContentBlock>[];
  for (final block in candidates) {
    final r = _rankable(block, profile, calibratedTaskElo[block.blockId]);
    if (r != null) {
      ranked.add(r);
    } else {
      unrankable.add(block);
    }
  }

  final selected = <ContentBlock>[];
  final chosen = <String>{};
  void take(Iterable<ContentBlock> blocks) {
    for (final block in blocks) {
      if (selected.length >= limit) return;
      if (chosen.add(block.blockId)) selected.add(block);
    }
  }

  // 2–3. Per domain while the student asked for several of them, so no single
  // domain can take the whole quiz (BR-ZQABZN). The order is shuffled: with a
  // remainder to hand out, the extra slot must not always fall to N.
  if (domains.length >= 2) {
    final byDomain = <GpfDomain, List<_RankableBlock>>{};
    for (final domain in domains) {
      final blocks = ranked.where((r) => r.touches(domain)).toList();
      if (blocks.isNotEmpty) byDomain[domain] = blocks;
    }
    if (byDomain.length >= 2) {
      final order = byDomain.keys.toList()..shuffle(rng);
      final share = limit ~/ order.length;
      final remainder = limit % order.length;
      for (var i = 0; i < order.length; i++) {
        final quota = share + (i < remainder ? 1 : 0);
        take(_drawRanked(
          byDomain[order[i]]!
              .where((r) => !chosen.contains(r.block.blockId))
              .toList(),
          profile,
          quota,
          rng,
        ));
      }
    }
  }

  // The undivided draw: one chosen domain or none, and the slots a domain
  // left behind because its own candidates ran out.
  if (selected.length < limit) {
    take(_drawRanked(
      ranked.where((r) => !chosen.contains(r.block.blockId)).toList(),
      profile,
      limit - selected.length,
      rng,
    ));
  }

  // Fill up from whatever was left over (unrankable blocks, then the rest of
  // the ranked pool) so a thin candidate set still yields a full quiz.
  if (selected.length < limit) {
    final leftovers = <ContentBlock>[
      ...unrankable,
      ...ranked.map((r) => r.block),
      ...candidates,
    ].where((b) => !chosen.contains(b.blockId)).toList()
      ..shuffle(rng);
    take(leftovers);
  }

  return selected;
}
