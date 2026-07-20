import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:eduai/core/database/app_database.dart';
import 'package:eduai/core/services/work_time_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late WorkTimeTracker tracker;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tracker = WorkTimeTracker(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> heartbeatCount() async =>
      (await db.getUnsyncedWorkHeartbeats()).length;

  test('emits a heartbeat when active on a learning screen', () async {
    tracker.setLocation(courseId: 'math', lessonId: 'l1', context: 'lesson');
    tracker.markActive();

    await tracker.tick();

    final rows = await db.getUnsyncedWorkHeartbeats();
    expect(rows, hasLength(1));
    expect(rows.first.courseId, 'math');
    expect(rows.first.lessonId, 'l1');
    expect(rows.first.context, 'lesson');
    expect(rows.first.synced, isFalse);
  });

  test('no heartbeat when there was no activity this interval', () async {
    tracker.setLocation(courseId: 'math');

    await tracker.tick();

    expect(await heartbeatCount(), 0);
  });

  test('no heartbeat when no learning location is set', () async {
    tracker.markActive();

    await tracker.tick();

    expect(await heartbeatCount(), 0);
  });

  test('activity flag resets after each tick', () async {
    tracker.setLocation(courseId: 'math');
    tracker.markActive();

    await tracker.tick(); // emits
    await tracker.tick(); // no new activity → no emit

    expect(await heartbeatCount(), 1);
  });

  test('clearing location stops counting', () async {
    tracker.setLocation(courseId: 'math');
    tracker.clearLocation();
    tracker.markActive();

    await tracker.tick();

    expect(await heartbeatCount(), 0);
  });
}
