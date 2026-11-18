// BR-2MAU65 — the "Dovednosti v kurzu" card on the course page listed the
// learner's overall skills, always the first three GPF domains (Číslo, Míry,
// Geometrie), whatever the course practised. The app's intro course has no
// skill vectors at all and still showed those three.
//
// The card, and the wide layout's "Dovednosti" tab, now list only the domains
// the course's tasks exercise; a course that exercises none shows no card.
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eduai/core/database/app_database.dart';
import 'package:eduai/core/elo/elo_engine.dart' show kGpfDimensions;
import 'package:eduai/core/providers/core_providers.dart';
import 'package:eduai/core/strings/app_strings.dart';
import 'package:eduai/main.dart' show routeObserver;
import 'package:eduai/models/course_model.dart';
import 'package:eduai/models/skill_display_model.dart';
import 'package:eduai/pages/course_detail_page.dart' show CourseDetailPage;

/// The test-only Ahem font is far wider than the real one, so labels overflow
/// their rows. Cosmetic and test-only — same suppression the other shell tests
/// use.
void _ignoreOverflow() {
  final oldOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exception.toString().contains('overflowed')) return;
    oldOnError?.call(details);
  };
  addTearDown(() => FlutterError.onError = oldOnError);
}

const _names = {
  'N': 'Číslo a operace',
  'M': 'Míry',
  'G': 'Geometrie',
  'S': 'Statistika a pravděpodobnost',
  'A': 'Algebra',
};

/// What [skillDisplayProvider] hands out for a learner with an ELO profile:
/// every domain, in the fixed GPF order.
final _allSkills = [
  for (final e in _names.entries)
    SkillDisplay(
      id: e.key,
      name: e.value,
      category: 'Matematika',
      emoji: '•',
      level: 5,
      confidenceLow: 4,
      confidenceHigh: 6,
      difficulty: 'intermediate',
    ),
];

/// A question block; with [dimension] it carries a GPF vector exercising that
/// one dimension (relation 2), as authored tasks do.
Map<String, dynamic> _block(String id, {int? dimension}) => {
      'block_id': id,
      'type': 'question',
      'question': '$id?',
      'options': ['a', 'b'],
      'correct_answer': 1,
      if (dimension != null)
        'gpf': {
          'relation_vector': List<double>.generate(
              kGpfDimensions, (i) => i == dimension ? 2.0 : 0.0),
          'elo_vector': List<double?>.generate(
              kGpfDimensions, (i) => i == dimension ? 5.0 : null),
        },
    };

Course _course(List<Map<String, dynamic>> blocks) => Course.fromJsonData(
      id: 'c-1',
      data: {
        'name': 'Kurz',
        'emoji': '🧪',
        'blocks': blocks,
        'lessons': [
          {
            'lesson_id': 'l-1',
            'name': 'Lekce 1',
            'blocks': [
              for (var i = 0; i < blocks.length; i++)
                {'block_id': blocks[i]['block_id'], 'order': i},
            ],
          },
        ],
      },
    );

/// Like the intro course: tasks without any skill vector.
Course _introCourse() => _course([_block('q1'), _block('q2')]);

/// Tasks in Geometrie (dimension 22) and Algebra (dimension 29) only.
Course _geometryAlgebraCourse() => _course([
      _block('g', dimension: 22),
      _block('a', dimension: 29),
      _block('plain'),
    ]);

Future<void> _pump(WidgetTester tester, Course course, double width) async {
  _ignoreOverflow();
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, 2400);
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  // The page reads course progress out of the database on the first frame; the
  // real one opens a file and leaves a timer pending in the test.
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWithValue(db),
        activeUserStreamProvider.overrideWith((ref) => Stream.value(null)),
        userStatsStreamProvider.overrideWith((ref) => Stream.value(null)),
        skillDisplayProvider.overrideWith((ref) async => _allSkills),
      ],
      child: MaterialApp(
        navigatorObservers: [routeObserver],
        home: CourseDetailPage(course: course),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  // The reporter's screen: Windows, Chrome, 1536px wide.
  const desktopWidth = 1536.0;
  const phoneWidth = 390.0;

  for (final (label, width) in [
    ('desktop', desktopWidth),
    ('phone', phoneWidth),
  ]) {
    testWidgets('$label: a course without skill vectors shows no skill card',
        (tester) async {
      await _pump(tester, _introCourse(), width);

      expect(find.text(AppStrings.courseSkillsInCourse), findsNothing);
      for (final name in _names.values) {
        expect(find.text(name), findsNothing,
            reason: '$name is not practised by this course');
      }
    });

    testWidgets('$label: the card lists only the domains the course practises',
        (tester) async {
      await _pump(tester, _geometryAlgebraCourse(), width);

      expect(find.text(AppStrings.courseSkillsInCourse), findsOneWidget);
      expect(find.text('Geometrie'), findsOneWidget);
      expect(find.text('Algebra'), findsOneWidget);
      for (final name in ['Číslo a operace', 'Míry',
        'Statistika a pravděpodobnost']) {
        expect(find.text(name), findsNothing,
            reason: '$name is not practised by this course');
      }
    });
  }

  testWidgets('desktop: the Dovednosti tab lists only the course\'s domains',
      (tester) async {
    await _pump(tester, _geometryAlgebraCourse(), desktopWidth);

    await tester.tap(find.text(AppStrings.courseTabSkills));
    await tester.pump();

    // Once in the tab, once in the rail card.
    expect(find.text('Geometrie'), findsNWidgets(2));
    expect(find.text('Algebra'), findsNWidgets(2));
    expect(find.text('Číslo a operace'), findsNothing);
  });

  testWidgets('desktop: the Dovednosti tab says so when the course has none',
      (tester) async {
    await _pump(tester, _introCourse(), desktopWidth);

    await tester.tap(find.text(AppStrings.courseTabSkills));
    await tester.pump();

    expect(find.text(AppStrings.courseSkillsNone), findsOneWidget);
    expect(find.text('Číslo a operace'), findsNothing);
  });
}
