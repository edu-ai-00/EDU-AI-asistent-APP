import 'dart:async';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';

/// Records active work-time heartbeats (BR-9SAH2R).
///
/// Learning screens register the user's location via [setLocation]; genuine
/// user interaction calls [markActive] (fed from the app-wide pointer
/// listener). Every [interval] the tracker writes one heartbeat row — but only
/// if there was activity since the last tick AND a location is set. Idle time
/// and time outside a learning screen are therefore not counted. Rows are
/// flushed to the API by SyncService.
class WorkTimeTracker {
  final AppDatabase _db;
  final Uuid _uuid;
  final Duration interval;

  String? _courseId;
  String? _lessonId;
  String? _context;
  bool _activeSinceTick = false;
  Timer? _timer;

  WorkTimeTracker(
    this._db, {
    this.interval = const Duration(seconds: 60),
    Uuid uuid = const Uuid(),
  }) : _uuid = uuid;

  /// Called by a learning screen when it becomes the active surface.
  void setLocation({required String courseId, String? lessonId, String? context}) {
    _courseId = courseId;
    _lessonId = lessonId;
    _context = context;
  }

  /// Called when the user leaves a learning screen.
  void clearLocation() {
    _courseId = null;
    _lessonId = null;
    _context = null;
  }

  /// Register genuine user interaction since the last tick.
  void markActive() => _activeSinceTick = true;

  void start() {
    _timer ??= Timer.periodic(interval, (_) => tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Emit a heartbeat when the user was active on a learning screen this
  /// interval. Public so it can be driven directly in tests.
  Future<void> tick() async {
    final courseId = _courseId;
    final wasActive = _activeSinceTick;
    _activeSinceTick = false;

    if (!wasActive || courseId == null) return;

    await _db.insertWorkHeartbeat(WorkHeartbeatsTableCompanion.insert(
      clientUuid: _uuid.v4(),
      courseId: courseId,
      lessonId: Value(_lessonId),
      context: Value(_context),
      occurredAt: DateTime.now().toUtc(),
    ));
  }
}
