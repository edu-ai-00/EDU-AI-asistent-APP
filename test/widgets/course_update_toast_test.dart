// BR-MKQ7H6 — after "Aktualizovat" on a phone-width course page, the green
// "Kurz … byl aktualizován" bar covered the Lekce / Cvičení / Kvíz row for its
// three seconds, so the student could not start the course until it went away.
//
// The row is a `Positioned` at the bottom of the page's own `Stack`, not the
// `Scaffold`'s `bottomNavigationBar`, so a floating `SnackBar` has no idea it is
// there and lands right on top of it. The client asked for the message at the
// top edge instead.
import 'dart:async';
import 'dart:convert';
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
import 'package:eduai/core/strings/app_strings.dart';
import 'package:eduai/core/sync/sync_service.dart';
import 'package:eduai/core/theme/app_theme.dart';
import 'package:eduai/core/ui/app_toast.dart';
import 'package:eduai/data/repositories/course_repository.dart'
    show CourseRepository;
import 'package:eduai/main.dart' show routeObserver;
import 'package:eduai/models/course_model.dart';
import 'package:eduai/pages/course_detail_page.dart' show CourseDetailPage;

const _courseId = 'c-1';
const _userCourseId = 'uc-1';
const _title = 'Funkce a grafy ZŠ';

Map<String, dynamic> _courseData() => {
      'course_id': 'Funkce_c1',
      'name': _title,
      'blocks': [
        {
          'block_id': 'b-1',
          'type': 'question',
          'question': '1 + 1?',
          'options': ['1', '2'],
          'correct_answer': 1,
        },
      ],
      'lessons': [
        {
          'lesson_id': 'L1',
          'name': 'Soustava souřadnic a lineární funkce',
          'blocks': [
            {'block_id': 'b-1', 'order': 0},
          ],
        },
      ],
    };

/// No network: the page's own update check stays local.
class _Offline implements ConnectivityService {
  @override
  Future<bool> get isOnline async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Stands in for the R2 download: the stored JSON is already the "new" one.
class _FakeCourseRepository implements CourseRepository {
  @override
  Future<bool> checkCourseVersionOnly(String localId) async => false;

  @override
  Future<bool> downloadFullCourseJson(String localId) async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoSync implements SyncService {
  @override
  Future<void> sync() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Keeps every HTTP request pending, so google_fonts' runtime fetches (let
/// through by `runAsync`) neither land nor fail the test.
class _SilentHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _SilentHttpClient();
}

class _SilentHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      Completer<HttpClientRequest>().future;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// The test-only Ahem font is far wider than the real one, so labels overflow
/// their rows. Cosmetic and test-only.
void _ignoreOverflow() {
  final oldOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exception.toString().contains('overflowed')) return;
    oldOnError?.call(details);
  };
  addTearDown(() => FlutterError.onError = oldOnError);
}

Future<void> _settleAsync(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
}

/// A course whose stored version is ahead of the downloaded one, so the page
/// offers "Aktualizovat" in place of the action row.
Future<void> _pumpOutdatedCourse(WidgetTester tester, Size size) async {
  _ignoreOverflow();
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);

  final data = _courseData();
  await tester.runAsync(() async {
    await db.upsertCourse(CoursesTableCompanion(
      id: const Value(_courseId),
      courseId: const Value('Funkce_c1'),
      name: const Value(_title),
      version: const Value(2),
      data: Value(jsonEncode(data)),
    ));
    await db.upsertUserCourse(UserCoursesTableCompanion(
      id: const Value(_userCourseId),
      userId: const Value('u-1'),
      courseId: const Value(_courseId),
      status: const Value('in_progress'),
      downloadedVersion: const Value(1),
      progressDataJson: Value(jsonEncode({'lessons': {}})),
    ));
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWithValue(db),
        authTokenStorageProvider
            .overrideWithValue(AuthTokenStorage(prefs: prefs)),
        connectivityServiceProvider.overrideWithValue(_Offline()),
        courseRepositoryProvider.overrideWithValue(_FakeCourseRepository()),
        syncServiceProvider.overrideWithValue(_NoSync()),
        activeUserStreamProvider.overrideWith((ref) => Stream.value(null)),
        userStatsStreamProvider.overrideWith((ref) => Stream.value(null)),
      ],
      child: MaterialApp(
        navigatorObservers: [routeObserver],
        // Same wiring as `MyApp.build`: the toast host and the responsive snack
        // bar theme sit above the Navigator.
        builder: (context, child) => Theme(
          data: Theme.of(context).copyWith(
            snackBarTheme: AppTheme.snackBarThemeFor(context),
          ),
          child: ToastHost(child: child ?? const SizedBox.shrink()),
        ),
        home: CourseDetailPage(
          course: Course.fromJsonData(id: _courseId, data: data),
          userCourseId: _userCourseId,
        ),
      ),
    ),
  );
  await _settleAsync(tester);
}

Future<void> _runUpdate(WidgetTester tester) async {
  final update = find.text(AppStrings.libraryUpdate);
  expect(update, findsOneWidget, reason: 'the page offers the update');
  await tester.tap(update);
  await _settleAsync(tester);
  // Let the toast's entry animation finish.
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  HttpOverrides? previousHttpOverrides;
  setUp(() {
    previousHttpOverrides = HttpOverrides.current;
    HttpOverrides.global = _SilentHttpOverrides();
  });
  tearDown(() => HttpOverrides.global = previousHttpOverrides);

  final updated = find.text(AppStrings.libraryCourseUpdated(_title));

  testWidgets('on a phone the message sits at the top, clear of the Lekce row',
      (tester) async {
    const size = Size(390, 844);
    await _pumpOutdatedCourse(tester, size);
    await _runUpdate(tester);

    expect(updated, findsOneWidget);
    expect(find.byType(SnackBar), findsNothing,
        reason: 'a bottom snack bar is what covered the action row');

    final toast = tester.getRect(updated);
    expect(toast.bottom, lessThan(size.height / 4),
        reason: 'the client asked for the message at the top edge');
    expect(toast.left, greaterThanOrEqualTo(0));
    expect(toast.right, lessThanOrEqualTo(size.width));

    // The action row is back after the update and must stay reachable.
    final lessons = find.text(AppStrings.courseActionLessons);
    expect(lessons, findsWidgets);
    for (final element in lessons.evaluate()) {
      final button = tester.getRect(find.byWidget(element.widget));
      expect(toast.overlaps(button), isFalse,
          reason: 'the message must not cover the Lekce button');
    }
  });

  testWidgets('on a desktop it is the corner toast, not a window-wide bar',
      (tester) async {
    const size = Size(1536, 872);
    await _pumpOutdatedCourse(tester, size);
    await _runUpdate(tester);

    expect(updated, findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    final toast = tester.getRect(updated);
    expect(toast.top, lessThan(80));
    expect(toast.right, greaterThan(size.width - 60));
  });
}
