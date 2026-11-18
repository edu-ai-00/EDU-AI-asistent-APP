// Regression test for BR-RQAVPY.
//
// The Úspěchy page is pushed with the student's earned achievement IDs as a
// snapshot. Its three openers (profile, dashboard, course detail) took that
// snapshot with `ref.read(earnedAchievementsProvider).valueOrNull` — but
// nothing in the app listens to that provider. Riverpod builds an unlistened
// provider only when it is read, and drops its database subscription whenever
// the active-user row is written, so the plain read found it still loading:
// an empty set on every first visit, a stale one after that. The page drew all
// six trophies faded while the Trofeje card above them counted 1, later 4.
// The openers now read the IDs straight from the database.
//
//   flutter test test/achievements_earned_ids_test.dart
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eduai/core/database/app_database.dart';
import 'package:eduai/core/providers/core_providers.dart';
import 'package:eduai/models/gamification_config_model.dart';
import 'package:eduai/pages/achievements_page.dart';

const _userId = 'guest-1';

void main() {
  group('readEarnedAchievementIds', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await db.upsertUser(const UsersTableCompanion(
        id: Value(_userId),
        name: Value('Chytry Panda'),
        email: Value(''),
        isActive: Value(true),
      ));
    });

    tearDown(() => db.close());

    Future<void> earn(String achievementId, {String userId = _userId}) =>
        db.insertAchievement(
          id: 'ach-$userId-$achievementId',
          userId: userId,
          achievementId: achievementId,
          earnedAt: DateTime.utc(2026, 11, 16, 12),
        );

    Future<Set<String>> openAchievements() => readEarnedAchievementIds(db);

    test('the first visit sees the trophy earned in lesson 1', () async {
      await earn('trophy_first_lesson');

      expect(await openAchievements(), {'trophy_first_lesson'});
    });

    test('a later visit sees what was earned since', () async {
      await earn('trophy_first_lesson');
      expect(await openAchievements(), {'trophy_first_lesson'});

      // The sync pull rewrites the user row after a lesson.
      await db.updateUserName(_userId, 'Chytry Panda');
      await earn('trophy_first_course');

      expect(await openAchievements(),
          {'trophy_first_lesson', 'trophy_first_course'});
    });

    test("another account's trophies on the device are not shown", () async {
      await db.upsertUser(const UsersTableCompanion(
        id: Value('pupil-2'),
        name: Value('Zvědavý orel'),
        email: Value(''),
        isActive: Value(false),
      ));
      await earn('trophy_first_quiz', userId: 'pupil-2');
      await earn('trophy_first_lesson');

      expect(await openAchievements(), {'trophy_first_lesson'});
    });

    test('no active user yields an empty set, not an error', () async {
      await earn('trophy_first_lesson');
      await db.logoutUser();

      expect(await openAchievements(), isEmpty);
    });
  });

  group('trophy grid', () {
    Future<void> pumpPage(WidgetTester tester, Set<String> earnedIds) async {
      tester.view.physicalSize = const Size(400, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: AchievementsPage(trophiesCount: 1, earnedIds: earnedIds),
      ));
    }

    double opacityOf(WidgetTester tester, String icon) => tester
        .widget<Opacity>(find
            .ancestor(of: find.text(icon).first, matching: find.byType(Opacity))
            .first)
        .opacity;

    final trophies = GamificationConfig.defaultConfig.trophies;
    final firstLesson =
        trophies.firstWhere((t) => t.id == 'trophy_first_lesson');
    final firstQuiz = trophies.firstWhere((t) => t.id == 'trophy_first_quiz');

    testWidgets('an earned trophy is drawn earned, the rest faded',
        (tester) async {
      await pumpPage(tester, {'trophy_first_lesson'});

      expect(opacityOf(tester, firstLesson.icon), 1.0);
      expect(opacityOf(tester, firstQuiz.icon), lessThan(1.0));
    });

    testWidgets('every trophy names itself on hover', (tester) async {
      await pumpPage(tester, const {});

      for (final t in trophies) {
        expect(
          find.byWidgetPredicate((w) =>
              w is Tooltip && (w.message ?? '').startsWith(t.title)),
          findsOneWidget,
          reason: t.id,
        );
      }
    });
  });
}
