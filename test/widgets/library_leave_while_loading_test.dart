// BR-M32MT5 (Sentry EDUAI-APP-4): "Null check operator used on a null value"
// on web. Knihovna reads the user's courses from the local DB when it opens
// and called `setState` once the read came back, without asking whether the
// page was still there. Leave the library before the read finishes and the
// `setState` lands on a disposed page: an assertion in debug, `_element!` on
// null in release. Starting a course update had the same gap.
//
// The DB below holds those reads until the test lets them finish, so the page
// can be closed in between.
import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eduai/core/database/app_database.dart';
import 'package:eduai/core/layout/breakpoints.dart';
import 'package:eduai/core/providers/core_providers.dart';
import 'package:eduai/core/strings/app_strings.dart';
import 'package:eduai/core/sync/sync_status.dart';
import 'package:eduai/data/repositories/course_repository.dart';
import 'package:eduai/pages/knihovna_page.dart';

class _SlowDatabase extends AppDatabase {
  _SlowDatabase() : super.forTesting(NativeDatabase.memory());

  UsersTableData? user;
  List<UserCoursesTableData> userCourses = const [];

  /// While set, [getActiveUser] waits for it.
  Completer<void>? holdActiveUser;

  /// While set, [getUserCourses] waits for it.
  Completer<void>? holdUserCourses;

  @override
  Future<UsersTableData?> getActiveUser() async {
    await holdActiveUser?.future;
    return user;
  }

  @override
  Future<List<UserCoursesTableData>> getUserCourses(String userId,
      {String? status}) async {
    await holdUserCourses?.future;
    return userCourses;
  }
}

/// A catalogue that never reaches the network.
class _Catalogue extends Fake implements CourseRepository {
  _Catalogue(this.courses);

  final List<Course> courses;

  @override
  Stream<List<Course>> watchAllCourses() => Stream.value(courses);

  @override
  Future<List<Course>> refreshCourses() async => courses;
}

final DateTime _now = DateTime(2026, 11, 13);

Course _course({required int version}) => Course(
      id: 'course-1',
      courseId: 'course-1',
      name: 'Zlomky',
      version: version,
      status: 'published',
      language: 'cs',
      data: const {},
      syncStatus: SyncStatus.synced,
      createdAt: _now,
      updatedAt: _now,
    );

UserCoursesTableData _userCourse(String userId,
        {required int downloadedVersion}) =>
    UserCoursesTableData(
      id: 'uc-1',
      userId: userId,
      courseId: 'course-1',
      status: 'in_progress',
      progressPercent: 0,
      completedLessons: 0,
      totalLessons: 3,
      currentLessonIndex: 0,
      timeSpentSeconds: 0,
      progressDataJson: '{}',
      downloadedVersion: downloadedVersion,
      syncStatus: 0,
      createdAt: _now,
      updatedAt: _now,
    );

Future<(_SlowDatabase, ProviderContainer)> _setUp(
  WidgetTester tester, {
  List<Course> courses = const [],
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(kCompactMaxWidth - 1, 900);
  addTearDown(tester.view.reset);

  // The test-only Ahem font overflows some fixed-width rows. Cosmetic.
  final oldOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exception.toString().contains('overflowed')) return;
    oldOnError?.call(details);
  };
  addTearDown(() => FlutterError.onError = oldOnError);

  final db = _SlowDatabase();
  addTearDown(db.close);
  db.user = await tester.runAsync<UsersTableData?>(() async {
    final id = await db.createGuestUser();
    return db.getUserById(id);
  });

  final container = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      courseRepositoryProvider.overrideWithValue(_Catalogue(courses)),
    ],
  );
  addTearDown(container.dispose);
  return (db, container);
}

Future<void> _show(
  WidgetTester tester,
  ProviderContainer container,
  Widget home,
) =>
    tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: home),
      ),
    );

void main() {
  testWidgets('leaving Knihovna before its courses load does not throw',
      (tester) async {
    final (db, container) = await _setUp(tester);
    db.holdUserCourses = Completer<void>();

    await _show(tester, container, const KnihovnaPage());
    await tester.pump();

    // The user moves on (e.g. to Přehled) while the read is still running.
    await _show(tester, container, const SizedBox.shrink());
    expect(find.byType(KnihovnaPage), findsNothing);

    db.holdUserCourses!.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('leaving Knihovna right after tapping Aktualizovat does not throw',
      (tester) async {
    final (db, container) = await _setUp(
      tester,
      courses: [_course(version: 2)],
    );
    db.userCourses = [_userCourse(db.user!.id, downloadedVersion: 1)];

    await _show(tester, container, const KnihovnaPage());
    await tester.pumpAndSettle();

    final update = find.text(AppStrings.libraryUpdate);
    expect(update, findsOneWidget);

    db.holdActiveUser = Completer<void>();
    await tester.tap(update);
    await tester.pump();

    await _show(tester, container, const SizedBox.shrink());
    expect(find.byType(KnihovnaPage), findsNothing);

    db.holdActiveUser!.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
