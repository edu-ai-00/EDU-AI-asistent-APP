// BR-ESXSZY — earlier builds created a chat session the moment a mentor was
// picked, so students who typed nothing have empty sessions on their devices
// and on the server, which hands them to every device on the next pull. The
// history list leaves out a session until it has a message.
//
//   flutter test test/chat_session_list_hides_empty_test.dart
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eduai/core/database/app_database.dart';
import 'package:eduai/data/datasources/local/chat_local_datasource.dart';

void main() {
  late AppDatabase db;
  late ChatLocalDataSource local;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    local = ChatLocalDataSource(db);
  });
  tearDown(() => db.close());

  Future<void> insertSession(String id, {String userId = 'u1'}) =>
      local.insertSession(ChatSessionsTableCompanion(
        id: Value(id),
        userId: Value(userId),
        persona: const Value('skolnik'),
      ));

  Future<void> insertMessage(String sessionId) =>
      local.insertMessage(ChatMessagesTableCompanion(
        id: Value('m-$sessionId'),
        sessionId: Value(sessionId),
        role: const Value('user'),
        content: const Value('Jak omluvit absenci?'),
      ));

  test('a session without messages stays out of the history', () async {
    await insertSession('empty');
    await insertSession('talked');
    await insertMessage('talked');

    final sessions = await local.watchSessions('u1').first;

    expect(sessions.map((s) => s.id), ['talked']);
  });

  test('a session shows up once its first message is stored', () async {
    await insertSession('new');

    final emitted = local.watchSessions('u1').map(
          (sessions) => sessions.map((s) => s.id).toList(),
        );
    final expectation = expectLater(
      emitted,
      emitsInOrder([
        <String>[],
        ['new'],
      ]),
    );

    await Future<void>.delayed(Duration.zero);
    await insertMessage('new');
    await expectation;
  });

  test('still only lists the user\'s own conversations', () async {
    await insertSession('mine');
    await insertMessage('mine');
    await insertSession('theirs', userId: 'u2');
    await insertMessage('theirs');

    final sessions = await local.watchSessions('u1').first;

    expect(sessions.map((s) => s.id), ['mine']);
  });
}
