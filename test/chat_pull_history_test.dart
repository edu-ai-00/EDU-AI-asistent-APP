// Regression test: after logout + re-login the local user gets a NEW uuid.
// pullHistory() must re-key server-known sessions to the active user so the
// chat list (filtered by userId) shows them again — same as progress restore.
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eduai/core/connectivity/connectivity_service.dart';
import 'package:eduai/core/database/app_database.dart';
import 'package:eduai/core/network/api_client.dart';
import 'package:eduai/core/sync/sync_queue.dart';
import 'package:eduai/data/datasources/local/chat_local_datasource.dart';
import 'package:eduai/data/datasources/remote/chat_remote_datasource.dart';
import 'package:eduai/data/repositories/chat_repository.dart';

class _FakeRemote implements ChatRemoteDataSource {
  final List<dynamic> sessions;
  _FakeRemote(this.sessions);

  @override
  Future<ApiResult<List<dynamic>>> fetchSessions({String? since}) async =>
      ApiResult.success(sessions);

  @override
  Future<ApiResult<List<dynamic>>> fetchAllMessages({String? since}) async =>
      ApiResult.success(const []);

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _NoConn implements ConnectivityService {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _NoQueue implements SyncQueue {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('pullHistory re-keys an existing session to the active user', () async {
    // Session created under the PRE-logout local uuid.
    await db.into(db.chatSessionsTable).insert(ChatSessionsTableCompanion(
          id: const Value('local-1'),
          userId: const Value('old-uuid'),
          serverId: const Value(42),
          title: const Value('Math chat'),
          persona: const Value('ai_teacher'),
        ));

    final repo = ChatRepository(
      localDataSource: ChatLocalDataSource(db),
      remoteDataSource: _FakeRemote([
        {
          'id': 42,
          'title': 'Math chat',
          'persona': 'ai_teacher',
          'last_message_at': DateTime.now().toIso8601String(),
        },
      ]),
      connectivity: _NoConn(),
      syncQueue: _NoQueue(),
    );

    // Re-login: brand-new local uuid is now the active user.
    await repo.pullHistory('new-uuid');

    final rows = await db.select(db.chatSessionsTable).get();
    expect(rows, hasLength(1), reason: 'must not duplicate by serverId');
    expect(rows.single.userId, 'new-uuid',
        reason: 'session must follow the re-logged-in user');
  });
}
