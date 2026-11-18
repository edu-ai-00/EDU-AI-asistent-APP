// BR-QRTHCM — on a tablet-width window the dashboard's "Moje kurzy" filter
// chips were wedged between the heading and "Zobrazit všechny". The row
// scrolls, so at 685px it showed "Všechny" and half of "Pr…", cut off
// mid-letter right where the link starts: a button that looks broken.
//
// The chips now share the heading's line only when every one of them fits on
// it whole; otherwise they drop to a line of their own under the heading.
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eduai/core/database/app_database.dart';
import 'package:eduai/core/providers/core_providers.dart';
import 'package:eduai/core/providers/practice_providers.dart';
import 'package:eduai/core/services/practice_filter_store.dart';
import 'package:eduai/core/strings/app_strings.dart';
import 'package:eduai/core/sync/sync_status.dart';
import 'package:eduai/data/repositories/user_course_repository.dart';
import 'package:eduai/pages/prehled_page.dart';
import 'package:eduai/pages/quiz_page.dart' show QuizProgress;
import 'package:eduai/widgets/filter_chip_row.dart';

/// The test-only Ahem font is far wider than the real one, so labels overflow
/// their rows. Cosmetic and test-only — same suppression the other dashboard
/// tests use.
void _ignoreOverflow() {
  final oldOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exception.toString().contains('overflowed')) return;
    oldOnError?.call(details);
  };
  addTearDown(() => FlutterError.onError = oldOnError);
}

UserCourse _course() {
  final now = DateTime(2026, 1, 1);
  return UserCourse(
    id: 'uc',
    userId: 'user',
    courseId: 'course',
    status: UserCourseStatus.downloaded,
    progressPercent: 0,
    completedLessons: 0,
    totalLessons: 2,
    currentLessonIndex: 0,
    timeSpentSeconds: 0,
    progressData: const {},
    downloadedVersion: 1,
    syncStatus: SyncStatus.synced,
    createdAt: now,
    updatedAt: now,
    courseName: 'Funkce a grafy ZŠ',
    courseData: const {
      'title': 'Funkce a grafy ZŠ',
      'description': 'Procvičíme si práci se souřadnicemi.',
      'emoji': '📖',
    },
  );
}

Future<List<Override>> _overrides() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  // The dashboard reads the course table directly (the JPZ banner asks whether
  // that course has arrived), so it needs a database.
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);

  return [
    sharedPreferencesProvider.overrideWithValue(prefs),
    appDatabaseProvider.overrideWithValue(db),
    activeUserStreamProvider.overrideWith((ref) => Stream.value(null)),
    userStatsStreamProvider.overrideWith((ref) => Stream.value(null)),
    userCoursesStreamProvider.overrideWith((ref) => Stream.value([_course()])),
    dueCardsCountProvider.overrideWith((ref) async => 0),
    practiceFilterProvider.overrideWith(
      (ref) => PracticeFilterNotifier(PracticeFilterStore(prefs)),
    ),
  ];
}

Future<void> _pumpDashboard(WidgetTester tester, double width) async {
  _ignoreOverflow();
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, 2000);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: await _overrides(),
      child: const MaterialApp(
        home: Scaffold(
          body: PrehledPage(quizProgressCache: <String, QuizProgress>{}),
        ),
      ),
    ),
  );
  await tester.pump();
}

List<String> get _chipLabels => [
  AppStrings.filterAll,
  AppStrings.filterInProgress,
  AppStrings.filterNotStarted,
  AppStrings.filterCompleted,
];

/// The chip box (border and padding included), not just its label.
Finder _chip(String label) => find
    .ancestor(
      of: find.descendant(
        of: find.byType(FilterChipRow),
        matching: find.text(label),
      ),
      matching: find.byType(Container),
    )
    .first;

/// Every chip lies wholly inside the strip the chip row shows — none of them
/// is scrolled off or sliced by its edge.
void _expectEveryChipWhole(WidgetTester tester) {
  final strip = tester.getRect(find.byType(FilterChipRow));
  for (final label in _chipLabels) {
    final chip = tester.getRect(_chip(label));
    expect(
      chip.left >= strip.left && chip.right <= strip.right,
      isTrue,
      reason:
          '"$label" spans ${chip.left}–${chip.right}, '
          'the chip row shows ${strip.left}–${strip.right}',
    );
  }
}

final _heading = find.text(AppStrings.sectionMyCourses);
final _showAll = find.text(AppStrings.sectionShowAllCourses);

void main() {
  testWidgets(
    'a tablet too narrow for one line puts the chips under the heading, '
    'all of them whole',
    (tester) async {
      // Medium width class, no side rail: the main column is too narrow for
      // heading + chips + link, but wide enough for the chips alone.
      await _pumpDashboard(tester, 860);

      _expectEveryChipWhole(tester);

      final heading = tester.getRect(_heading);
      final firstChip = tester.getRect(_chip(AppStrings.filterAll));
      expect(firstChip.top, greaterThanOrEqualTo(heading.bottom));
      // Lined up with the heading rather than indented by the row's padding.
      expect(firstChip.left, moreOrLessEquals(heading.left, epsilon: 1));

      // The link stays on the heading's line, at its far end.
      final showAll = tester.getRect(_showAll);
      expect(showAll.center.dy, moreOrLessEquals(heading.center.dy));
      expect(showAll.right, greaterThan(firstChip.right));
    },
  );

  testWidgets(
    'a window wide enough keeps heading, chips and link on one line',
    (tester) async {
      await _pumpDashboard(tester, 2000);

      _expectEveryChipWhole(tester);

      final heading = tester.getRect(_heading);
      final lastChip = tester.getRect(_chip(AppStrings.filterCompleted));
      final showAll = tester.getRect(_showAll);
      expect(lastChip.center.dy, moreOrLessEquals(heading.center.dy));
      expect(lastChip.left, greaterThan(heading.right));
      expect(showAll.left, greaterThan(lastChip.right));
    },
  );
}
