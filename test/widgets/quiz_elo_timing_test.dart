import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eduai/core/database/app_database.dart';
import 'package:eduai/core/elo/elo_engine.dart';
import 'package:eduai/core/providers/core_providers.dart';
import 'package:eduai/core/services/gaming_reference_service.dart';
import 'package:eduai/core/services/work_time_tracker.dart';
import 'package:eduai/core/strings/app_strings.dart';
import 'package:eduai/core/sync/sync_service.dart';
import 'package:eduai/data/repositories/elo_repository.dart';
import 'package:eduai/models/block_model.dart';
import 'package:eduai/pages/quiz_page.dart';

// Regression test for BR-PTSQDD.
//
// A quiz without evaluation moves on to the next question in the frame after
// the answer, while the ELO update is still awaiting the database. The update
// read the question index only after those awaits, so it logged the NEXT
// question's open time as opened_at and "now" as confirmed_at — the ELO CSV
// export showed Otevřeno = Potvrzeno and Doba 0s on every quiz row.

const _userId = 'user-1';

ContentBlock _question(String blockId) {
  final relation = List<int>.filled(kGpfDimensions, 0)..[0] = 2;
  final elo = List<double?>.filled(kGpfDimensions, null)..[0] = 6.0;
  return ContentBlock.fromJson({
    'block_id': blockId,
    'type': 'question',
    'content': 'Kolik je 2 + 2?',
    'gpf': {'relation_vector': relation, 'elo_vector': elo},
    'question': {
      'type': 'multiple_choice',
      'options': [
        {'id': 'a', 'text': '3', 'is_correct': false},
        {'id': 'b', 'text': '4', 'is_correct': true},
      ],
    },
  });
}

/// On a device the database sits behind a worker / isolate, and the ELO
/// update's queries together outlive the frame the quiz advances in. The
/// in-memory test database answers within the same microtask flush; this
/// puts the device's latency back. Longer than the first pump step of
/// pumpAndSettle (100 ms), which elapses before that frame is drawn.
class _DeviceLatencyEloRepository extends EloRepository {
  _DeviceLatencyEloRepository({required super.db});

  @override
  Future<UserEloProfile> getOrCreateProfile(String userId) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    return super.getOrCreateProfile(userId);
  }
}

class _NoReference implements GamingReferenceService {
  @override
  Future<Map<String, List<double>>> fetch(Iterable<String> blockIds) async =>
      const {};
}

class _NoSync implements SyncService {
  @override
  Future<void> sync() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// google_fonts fetches its fonts over HTTP. The test binding answers every
/// request with 400, and inside the real-async windows below that failure
/// lands as a test error; a request that never answers stays silent.
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
  late HttpOverrides? previousHttpOverrides;

  setUp(() async {
    previousHttpOverrides = HttpOverrides.current;
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
  });

  tearDown(() async {
    HttpOverrides.global = previousHttpOverrides;
    await db.close();
  });

  testWidgets('a quiz answer logs its own question\'s open and confirm times',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(prefs),
      workTimeTrackerProvider.overrideWithValue(WorkTimeTracker(db)),
      syncServiceProvider.overrideWithValue(_NoSync()),
      gamingReferenceServiceProvider.overrideWithValue(_NoReference()),
      eloRepositoryProvider
          .overrideWithValue(_DeviceLatencyEloRepository(db: db)),
    ]);
    addTearDown(container.dispose);
    await tester.runAsync(() => container.read(activeUserProvider.future));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: QuizPage(
            questionBlocks: [_question('Q1'), _question('Q2')],
            courseTitle: 'Kvíz',
            courseId: 'C-QUIZ',
            // No evaluation: the quiz moves on right after the answer.
            evaluate: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Spend real time on the first question — the quiz times answers on the
    // wall clock — past the 2 s gaming floor so the answer moves ELO.
    final shownAfter = DateTime.now().toUtc();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2100)));

    await tester.tap(find.text('4'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.actionContinue));
    await tester.pumpAndSettle();
    // Let the database answer the ELO update — Q2 is on screen by now.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    final queued = (await tester.runAsync(() => (db.select(db.syncQueueTable)
          ..where((q) => q.tableName_.equals('elo_interactions')))
        .get()))!;
    expect(queued, hasLength(1));
    final payload = jsonDecode(queued.single.payload) as Map<String, dynamic>;
    expect(payload['block_id'], 'Q1');

    final openedAt = DateTime.parse(payload['opened_at'] as String);
    final confirmedAt = DateTime.parse(payload['confirmed_at'] as String);
    expect(openedAt.isAfter(shownAfter), isFalse,
        reason: 'opened when Q1 was shown, not when Q2 was');
    expect(confirmedAt.difference(openedAt).inMilliseconds,
        greaterThanOrEqualTo(2000));
    expect(payload['duration_ms'], greaterThanOrEqualTo(2000));
    expect(payload['duration_ms'],
        confirmedAt.difference(openedAt).inMilliseconds);
  });
}
