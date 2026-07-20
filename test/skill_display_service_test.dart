// Coverage for BR-N2E9MF: skill card domain titles must come from the backend
// Czech vector labeling (passed in as domainNames), not hardcoded English.
import 'package:flutter_test/flutter_test.dart';

import 'package:eduai/core/elo/skill_display_service.dart';

void main() {
  // 35-dim profile with every dimension answered enough to be eligible.
  List<double?> elo() => List<double?>.filled(35, 6.0);
  List<int> pocet() => List<int>.filled(35, 10);

  const czech = {
    'N': 'Číslo a operace',
    'M': 'Míry',
    'G': 'Geometrie',
    'S': 'Statistika a pravděpodobnost',
    'A': 'Algebra',
  };

  test('domain titles resolve to the Czech labels supplied by the backend', () {
    final skills = SkillDisplayService.computeSkills(
      profilElo: elo(),
      profilPocet: pocet(),
      domainNames: czech,
    );

    final names = skills.map((s) => s.name).toList();
    expect(names, [
      'Číslo a operace',
      'Míry',
      'Geometrie',
      'Statistika a pravděpodobnost',
      'Algebra',
    ]);
    // No English domain title leaks through.
    expect(names, isNot(contains('Number and operations')));
  });

  test('missing label falls back to the domain code, never English', () {
    final skills = SkillDisplayService.computeSkills(
      profilElo: elo(),
      profilPocet: pocet(),
      domainNames: const {'N': 'Číslo a operace'}, // others missing
    );

    final byCode = {for (final s in skills) s.id: s.name};
    expect(byCode['N'], 'Číslo a operace');
    expect(byCode['G'], 'G'); // fallback = code, not "Geometry"
  });
}
