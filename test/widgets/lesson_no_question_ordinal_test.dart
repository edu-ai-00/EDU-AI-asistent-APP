import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eduai/core/connectivity/connectivity_service.dart';
import 'package:eduai/core/database/app_database.dart';
import 'package:eduai/core/providers/core_providers.dart';
import 'package:eduai/core/services/auth_token_storage.dart';
import 'package:eduai/core/services/work_time_tracker.dart';
import 'package:eduai/core/strings/app_strings.dart';
import 'package:eduai/core/sync/sync_service.dart';
import 'package:eduai/data/repositories/gamification_config_repository.dart';
import 'package:eduai/models/gamification_config_model.dart';
import 'package:eduai/models/course_model.dart';
import 'package:eduai/pages/lesson_detail_page.dart';

// BR-CU5DPS — BR-VK9QJA had put "Otázka 1 / 7" above every question card of a
// lesson. The client does not want that line there, so the change was reverted;
// this pins the cards back to carrying no ordinal.

const _userId = 'user-1';
const _userCourseId = 'uc-1';

Map<String, dynamic> _question(String id) => {
      'block_id': id,
      'type': 'question',
      'steps': [
        {
          'id': 's1',
          'type': 'question',
          'order': 1,
          'question': {
            'type': 'multiple_choice',
            'question': 'Kolik je 2 + 2? ($id)',
            'options': [
              {'id': 'a', 'text': 'tri $id', 'is_correct': false},
              {'id': 'b', 'text': 'ctyri $id', 'is_correct': true},
            ],
          },
        },
      ],
    };

Map<String, dynamic> _text(String id) => {
      'block_id': id,
      'type': 'learning',
      'steps': [
        {
          'id': 's1',
          'type': 'text',
          'order': 1,
          'content': {'text': 'Cti dal.'},
        },
      ],
    };

/// One lesson holding [blocks], in that order.
Map<String, dynamic> _courseData(List<Map<String, dynamic>> blocks) => {
      'course_id': 'C-NUM',
      'name': 'Demo kurz',
      'language': 'cs',
      'lessons': [
        {
          'lesson_id': 'L1',
          'name': 'Otazky',
          'order': 1,
          'blocks': [
            for (var i = 0; i < blocks.length; i++)
              {'block_id': blocks[i]['block_id'], 'order': i + 1},
          ],
        },
      ],
      'blocks': blocks,
    };

/// Completing a block kicks off a sync; the real one wants a signed-in client.
class _NoSync implements SyncService {
  @override
  Future<void> sync() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Offline, so the trophy and streak writes queue up instead of calling the
/// API — which, with [_SilentHttpOverrides], would never answer.
class _Offline implements ConnectivityService {
  @override
  Future<bool> get isOnline async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// No achievements to check — the real repository would download the config.
class _NoGamificationConfig implements GamificationConfigRepository {
  @override
  Future<GamificationConfig?> getConfig() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// google_fonts fetches over HTTP; a request that never answers stays silent,
/// while the binding's own 400 lands as a test error inside a real-async gap.
class _SilentHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _NeverAnswering();
}

class _NeverAnswering implements HttpClient {
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      Completer<HttpClientRequest>().future;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late SharedPreferences prefs;

  setUp(() async {
    HttpOverrides.global = _SilentHttpOverrides();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.upsertUser(const UsersTableCompanion(
      id: Value(_userId),
      name: Value('Tester'),
      email: Value(''),
      isActive: Value(true),
    ));
    await db.upsertUserCourse(const UserCoursesTableCompanion(
      id: Value(_userCourseId),
      userId: Value(_userId),
      courseId: Value('local-1'),
      status: Value('in_progress'),
      totalLessons: Value(1),
    ));
  });

  // Not awaited: the page's drift watches close on zero-delay timers, and once
  // the container is disposed nothing pumps them any more.
  tearDown(() {
    db.close();
  });

  Future<void> pumpLesson(
    WidgetTester tester,
    List<Map<String, dynamic>> blocks,
  ) async {
    // Wide enough for the rail beside the lesson column — the layout the
    // report came from.
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(prefs),
      // No token: XP writes stay local, nothing goes out.
      authTokenStorageProvider.overrideWithValue(AuthTokenStorage(prefs: prefs)),
      workTimeTrackerProvider.overrideWithValue(WorkTimeTracker(db)),
      syncServiceProvider.overrideWithValue(_NoSync()),
      connectivityServiceProvider.overrideWithValue(_Offline()),
      gamificationConfigRepositoryProvider
          .overrideWithValue(_NoGamificationConfig()),
    ]);
    addTearDown(container.dispose);
    await tester.runAsync(() => container.read(activeUserProvider.future));

    final course = Course.fromJsonData(id: 'local-1', data: _courseData(blocks));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: LessonDetailPage(
            course: course,
            lesson: course.lessons.first,
            lessonIndex: 0,
            userCourseId: _userCourseId,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> answerRight(WidgetTester tester, String blockId) async {
    await tester.tap(find.text('ctyri $blockId'));
    await tester.pumpAndSettle();
    // "Zkontrolovat" grades the answer; the checkmark then steps past the
    // solution to the next block.
    await tapAndSettle(tester, find.text(AppStrings.engineCheck).last);
    await tapAndSettle(tester, find.byIcon(Icons.check).last);
  }

  /// Any "Otázka 1 / 3" / "Question 1 / 3" line on screen.
  final questionOrdinal = find.textContaining(
    RegExp(r'^(Otázka|Question) \d+ / \d+$'),
    findRichText: true,
  );

  testWidgets('question cards carry no "Otázka 1 / 2" line', (tester) async {
    await pumpLesson(tester, [_question('B1'), _question('B2'), _text('B3')]);

    expect(find.text('ctyri B1'), findsOneWidget,
        reason: 'the question card itself is on screen');
    expect(questionOrdinal, findsNothing);

    await answerRight(tester, 'B1');

    // Neither the answered card nor the one now open is numbered.
    expect(find.text('ctyri B2'), findsOneWidget);
    expect(questionOrdinal, findsNothing);
  });
}
