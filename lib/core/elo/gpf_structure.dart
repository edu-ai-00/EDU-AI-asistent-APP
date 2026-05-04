/// Static GPF (General Proficiency Framework) structure for the math vector.
///
/// Defines 5 domain groupings and 35 subconstruct metadata entries
/// that form the dimensions of the ELO profile vector.
library;

/// A top-level domain grouping in the GPF framework.
class GpfDomain {
  /// Short code identifying the domain (e.g. "N", "M", "G").
  final String code;

  /// Human-readable Czech name of the domain.
  final String name;

  /// Emoji representing the domain (Unicode).
  final String emoji;

  /// Indices of subconstructs belonging to this domain in the 35-dim vector.
  final List<int> indices;

  const GpfDomain({
    required this.code,
    required this.name,
    required this.emoji,
    required this.indices,
  });
}

/// A single subconstruct (dimension) in the 35-element GPF vector.
class GpfSubconstruct {
  /// Zero-based index in the 35-dim vector (0–34).
  final int index;

  /// Hierarchical identifier (e.g. "N1.1", "A3.4").
  final String id;

  /// Parent domain code (e.g. "N").
  final String domainCode;

  /// Parent domain name (e.g. "Číslo a operace").
  final String domainName;

  /// Construct name within the domain (e.g. "Přirozená čísla").
  final String constructName;

  /// Subconstruct description in Czech.
  final String name;

  const GpfSubconstruct({
    required this.index,
    required this.id,
    required this.domainCode,
    required this.domainName,
    required this.constructName,
    required this.name,
  });
}

/// Central registry of the GPF structure — domains and subconstructs.
///
/// All data is hardcoded from the confirmed GPF table and exposed as
/// compile-time constants with simple lookup helpers.
class GpfStructure {
  GpfStructure._();

  // ---------------------------------------------------------------------------
  // Domains
  // ---------------------------------------------------------------------------

  /// The 5 top-level GPF domains.
  static const List<GpfDomain> domains = [
    GpfDomain(
      code: 'N',
      name: 'Číslo a operace',
      emoji: '\u{1F9EE}', // 🧮
      indices: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16],
    ),
    GpfDomain(
      code: 'M',
      name: 'Míry',
      emoji: '\u{1F4CF}', // 📏
      indices: [17, 18, 19, 20, 21],
    ),
    GpfDomain(
      code: 'G',
      name: 'Geometrie',
      emoji: '\u{1F4D0}', // 📐
      indices: [22, 23, 24],
    ),
    GpfDomain(
      code: 'S',
      name: 'Statistika a pravděpodobnost',
      emoji: '\u{1F4CA}', // 📊
      indices: [25, 26, 27, 28],
    ),
    GpfDomain(
      code: 'A',
      name: 'Algebra',
      emoji: '\u{2696}\u{FE0F}', // ⚖️
      indices: [29, 30, 31, 32, 33, 34],
    ),
  ];

  // ---------------------------------------------------------------------------
  // Subconstructs
  // ---------------------------------------------------------------------------

  /// All 35 subconstructs in vector-index order.
  static const List<GpfSubconstruct> subconstructs = [
    // ── N1: Přirozená čísla ──────────────────────────────────────────────
    GpfSubconstruct(
      index: 0,
      id: 'N1.1',
      domainCode: 'N',
      domainName: 'Číslo a operace',
      constructName: 'Přirozená čísla',
      name: 'určí přirozená čísla a počítá s nimi, určí relativní velikost',
    ),
    GpfSubconstruct(
      index: 1,
      id: 'N1.2',
      domainCode: 'N',
      domainName: 'Číslo a operace',
      constructName: 'Přirozená čísla',
      name: 'znázorňuje přirozená čísla ekvivalentními způsoby',
    ),
    GpfSubconstruct(
      index: 2,
      id: 'N1.3',
      domainCode: 'N',
      domainName: 'Číslo a operace',
      constructName: 'Přirozená čísla',
      name: 'provádí operace s přirozenými čísly',
    ),
    GpfSubconstruct(
      index: 3,
      id: 'N1.4',
      domainCode: 'N',
      domainName: 'Číslo a operace',
      constructName: 'Přirozená čísla',
      name: 'řeší úlohy z reálného světa s použitím přirozených čísel',
    ),

    // ── N2: Zlomky ───────────────────────────────────────────────────────
    GpfSubconstruct(
      index: 4,
      id: 'N2.1',
      domainCode: 'N',
      domainName: 'Číslo a operace',
      constructName: 'Zlomky',
      name: 'určí a znázorní zlomky',
    ),
    GpfSubconstruct(
      index: 5,
      id: 'N2.2',
      domainCode: 'N',
      domainName: 'Číslo a operace',
      constructName: 'Zlomky',
      name: 'provádí operace se zlomky',
    ),
    GpfSubconstruct(
      index: 6,
      id: 'N2.3',
      domainCode: 'N',
      domainName: 'Číslo a operace',
      constructName: 'Zlomky',
      name: 'řeší úlohy z reálného světa s použitím zlomků',
    ),

    // ── N3: Desetinná čísla ──────────────────────────────────────────────
    GpfSubconstruct(
      index: 7,
      id: 'N3.1',
      domainCode: 'N',
      domainName: 'Číslo a operace',
      constructName: 'Desetinná čísla',
      name: 'určí a znázorní desetinná čísla',
    ),
    GpfSubconstruct(
      index: 8,
      id: 'N3.2',
      domainCode: 'N',
      domainName: 'Číslo a operace',
      constructName: 'Desetinná čísla',
      name: 'znázorní desetinná čísla ekvivalentními způsoby',
    ),
    GpfSubconstruct(
      index: 9,
      id: 'N3.3',
      domainCode: 'N',
      domainName: 'Číslo a operace',
      constructName: 'Desetinná čísla',
      name: 'řeší operace s desetinnými čísly',
    ),
    GpfSubconstruct(
      index: 10,
      id: 'N3.4',
      domainCode: 'N',
      domainName: 'Číslo a operace',
      constructName: 'Desetinná čísla',
      name: 'řeší úlohy z reálného světa s desetinnými čísly',
    ),

    // ── N4: Celá čísla ──────────────────────────────────────────────────
    GpfSubconstruct(
      index: 11,
      id: 'N4.1',
      domainCode: 'N',
      domainName: 'Číslo a operace',
      constructName: 'Celá čísla',
      name: 'určí a znázorní celá čísla',
    ),
    GpfSubconstruct(
      index: 12,
      id: 'N4.2',
      domainCode: 'N',
      domainName: 'Číslo a operace',
      constructName: 'Celá čísla',
      name: 'provádí operace s celými čísly',
    ),
    GpfSubconstruct(
      index: 13,
      id: 'N4.3',
      domainCode: 'N',
      domainName: 'Číslo a operace',
      constructName: 'Celá čísla',
      name: 'řeší úlohy z reálného světa s celými čísly',
    ),

    // ── N5: Mocniny a odmocniny ─────────────────────────────────────────
    GpfSubconstruct(
      index: 14,
      id: 'N5.1',
      domainCode: 'N',
      domainName: 'Číslo a operace',
      constructName: 'Mocniny a odmocniny',
      name: 'určí a znázorní veličiny pomocí mocnin a odmocnin',
    ),
    GpfSubconstruct(
      index: 15,
      id: 'N5.2',
      domainCode: 'N',
      domainName: 'Číslo a operace',
      constructName: 'Mocniny a odmocniny',
      name: 'řeší operace s mocninami a odmocninami',
    ),

    // ── N6: Operace napříč číselnými obory ──────────────────────────────
    GpfSubconstruct(
      index: 16,
      id: 'N6.1',
      domainCode: 'N',
      domainName: 'Číslo a operace',
      constructName: 'Operace napříč číselnými obory',
      name: 'řeší operace napříč číselnými obory',
    ),

    // ── M1: Délka, hmotnost, objem, obsah a obvod ───────────────────────
    GpfSubconstruct(
      index: 17,
      id: 'M1.1',
      domainCode: 'M',
      domainName: 'Míry',
      constructName: 'Délka, hmotnost, objem, obsah a obvod',
      name: 'používá nestandardní a standardní jednotky pro měření',
    ),
    GpfSubconstruct(
      index: 18,
      id: 'M1.2',
      domainCode: 'M',
      domainName: 'Míry',
      constructName: 'Délka, hmotnost, objem, obsah a obvod',
      name: 'řeší úlohy s rozměry',
    ),

    // ── M2: Čas ─────────────────────────────────────────────────────────
    GpfSubconstruct(
      index: 19,
      id: 'M2.1',
      domainCode: 'M',
      domainName: 'Míry',
      constructName: 'Čas',
      name: 'určí čas',
    ),
    GpfSubconstruct(
      index: 20,
      id: 'M2.2',
      domainCode: 'M',
      domainName: 'Míry',
      constructName: 'Čas',
      name: 'řeší úlohy s časem',
    ),

    // ── M3: Měna ────────────────────────────────────────────────────────
    GpfSubconstruct(
      index: 21,
      id: 'M3.1',
      domainCode: 'M',
      domainName: 'Míry',
      constructName: 'Měna',
      name: 'využívá různých mincí pro vytvoření celkových částek',
    ),

    // ── G1: Vlastnosti útvarů a obrazců ─────────────────────────────────
    GpfSubconstruct(
      index: 22,
      id: 'G1.1',
      domainCode: 'G',
      domainName: 'Geometrie',
      constructName: 'Vlastnosti útvarů a obrazců',
      name: 'určí a popíše útvary a obrazce',
    ),

    // ── G2: Prostorové vizualizace ──────────────────────────────────────
    GpfSubconstruct(
      index: 23,
      id: 'G2.1',
      domainCode: 'G',
      domainName: 'Geometrie',
      constructName: 'Prostorové vizualizace',
      name: 'skládá a rozkládá útvary a obrazce',
    ),

    // ── G3: Poloha a směr ───────────────────────────────────────────────
    GpfSubconstruct(
      index: 24,
      id: 'G3.1',
      domainCode: 'G',
      domainName: 'Geometrie',
      constructName: 'Poloha a směr',
      name: 'popisuje polohu a směr objektů v prostoru',
    ),

    // ── S1: Práce s daty ────────────────────────────────────────────────
    GpfSubconstruct(
      index: 25,
      id: 'S1.1',
      domainCode: 'S',
      domainName: 'Statistika a pravděpodobnost',
      constructName: 'Práce s daty',
      name: 'přečte a interpretuje graficky znázorněná data',
    ),
    GpfSubconstruct(
      index: 26,
      id: 'S1.2',
      domainCode: 'S',
      domainName: 'Statistika a pravděpodobnost',
      constructName: 'Práce s daty',
      name: 'vypočítá a interpretuje centrální tendenci',
    ),

    // ── S2: Náhoda a pravděpodobnost ────────────────────────────────────
    GpfSubconstruct(
      index: 27,
      id: 'S2.1',
      domainCode: 'S',
      domainName: 'Statistika a pravděpodobnost',
      constructName: 'Náhoda a pravděpodobnost',
      name: 'různými způsoby popisuje pravděpodobnost jevů',
    ),
    GpfSubconstruct(
      index: 28,
      id: 'S2.2',
      domainCode: 'S',
      domainName: 'Statistika a pravděpodobnost',
      constructName: 'Náhoda a pravděpodobnost',
      name: 'určí permutace a kombinace',
    ),

    // ── A1: Pravidelnosti ───────────────────────────────────────────────
    GpfSubconstruct(
      index: 29,
      id: 'A1.1',
      domainCode: 'A',
      domainName: 'Algebra',
      constructName: 'Pravidelnosti',
      name: 'určí, popíše, rozvine a vytvoří pravidelnosti',
    ),

    // ── A2: Výrazy ──────────────────────────────────────────────────────
    GpfSubconstruct(
      index: 30,
      id: 'A2.1',
      domainCode: 'A',
      domainName: 'Algebra',
      constructName: 'Výrazy',
      name: 'řeší a modeluje výrazy a počítá s nimi',
    ),

    // ── A3: Závislosti a funkce ─────────────────────────────────────────
    GpfSubconstruct(
      index: 31,
      id: 'A3.1',
      domainCode: 'A',
      domainName: 'Algebra',
      constructName: 'Závislosti a funkce',
      name: 'řeší úlohy se závislostmi',
    ),
    GpfSubconstruct(
      index: 32,
      id: 'A3.2',
      domainCode: 'A',
      domainName: 'Algebra',
      constructName: 'Závislosti a funkce',
      name: 'prokazuje porozumění rovnosti',
    ),
    GpfSubconstruct(
      index: 33,
      id: 'A3.3',
      domainCode: 'A',
      domainName: 'Algebra',
      constructName: 'Závislosti a funkce',
      name: 'řeší rovnice a nerovnice',
    ),
    GpfSubconstruct(
      index: 34,
      id: 'A3.4',
      domainCode: 'A',
      domainName: 'Algebra',
      constructName: 'Závislosti a funkce',
      name: 'interpretuje a vyhodnocuje funkce',
    ),
  ];

  // ---------------------------------------------------------------------------
  // Lookup helpers
  // ---------------------------------------------------------------------------

  /// Returns the [GpfDomain] matching [code], or `null` if not found.
  static GpfDomain? domainByCode(String code) {
    for (final domain in domains) {
      if (domain.code == code) return domain;
    }
    return null;
  }

  /// Returns the [GpfSubconstruct] at the given vector [index], or `null`
  /// if [index] is out of range.
  static GpfSubconstruct? subconstruct(int index) {
    if (index < 0 || index >= subconstructs.length) return null;
    return subconstructs[index];
  }
}
