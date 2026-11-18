// BR-ESXSZY — picking a mentor under "Nový chat" created the conversation on
// the spot, so a student who backed out without typing kept an empty chat in
// the history. Rule 11.6: a new conversation is created by the first message.
//
// The chat now opens without a session and ChatDetailPage creates it when the
// first message is sent — on a phone (pushed route) and in the wide layout's
// pane alike.
//
//   flutter test test/widgets/chat_new_chat_no_empty_session_test.dart
import 'dart:async';

import 'package:eduai/core/connectivity/connectivity_service.dart';
import 'package:eduai/core/database/app_database.dart';
import 'package:eduai/core/providers/core_providers.dart';
import 'package:eduai/core/strings/app_strings.dart';
import 'package:eduai/data/repositories/chat_repository.dart';
import 'package:eduai/models/chat_models.dart';
import 'package:eduai/pages/chat_detail_page.dart';
import 'package:eduai/pages/chaty_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// `dejepisec` stands for a mentor an admin added: ChatPersona does not know
/// it, so only its slug can create the session.
final _mentors = [
  const ChatMentor(
    slug: 'dejepisec',
    name: 'Dějepisec',
    description: 'Mentor přidaný v adminu.',
    emoji: '🏛️',
  ),
];

class _FakeChatRepo implements ChatRepository {
  final createdFor = <String>[];
  final sentTo = <String>[];

  @override
  Future<ChatSessionsTableData> createSession(
      String userId, String personaSlug) async {
    createdFor.add(personaSlug);
    final now = DateTime(2026, 11, 5, 13, 0);
    return ChatSessionsTableData(
      id: 's1',
      userId: userId,
      serverId: 42,
      title: '',
      persona: personaSlug,
      lastMessageAt: now,
      syncStatus: 'synced',
      createdAt: now,
      updatedAt: now,
    );
  }

  @override
  Stream<ChatStreamEvent> sendMessage(String sessionId, String content,
      {String? context}) {
    sentTo.add(sessionId);
    // Only a token: ChatStreamDone would kick off a real sync service.
    return Stream.value(ChatStreamToken('Dobrý den'));
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

UsersTableData _user() {
  final now = DateTime(2026, 1, 1);
  return UsersTableData(
    id: 'u1',
    email: 'student@example.com',
    name: 'Student',
    avatarIndex: 0,
    selectedSubjects: '[0]',
    isEmailValidated: true,
    isActive: true,
    syncStatus: 0,
    createdAt: now,
    updatedAt: now,
  );
}

/// The test-only Ahem font is far wider than the real one, so the header row
/// overflows. Cosmetic and test-only — same suppression the other chat tests
/// use.
void _ignoreOverflow() {
  final oldOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exception.toString().contains('overflowed')) return;
    oldOnError?.call(details);
  };
  addTearDown(() => FlutterError.onError = oldOnError);
}

ChatSessionsTableData _listed(String id, String title) {
  final now = DateTime(2026, 11, 5, 13, 1);
  return ChatSessionsTableData(
    id: id,
    userId: 'u1',
    serverId: 42,
    title: title,
    persona: 'dejepisec',
    lastMessageAt: now,
    syncStatus: 'synced',
    createdAt: now,
    updatedAt: now,
  );
}

Future<_FakeChatRepo> _pumpChatTab(
  WidgetTester tester,
  Size size, {
  Stream<List<ChatSessionsTableData>>? sessions,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  _ignoreOverflow();

  final repo = _FakeChatRepo();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        chatRepositoryProvider.overrideWithValue(repo),
        activeUserProvider.overrideWith((ref) async => _user()),
        chatMentorsProvider.overrideWith((ref) async => _mentors),
        chatSessionsStreamProvider.overrideWith(
          (ref) => sessions ?? Stream.value(const <ChatSessionsTableData>[]),
        ),
        chatMessagesStreamProvider.overrideWith(
          (ref, sessionId) => Stream.value(const <ChatMessagesTableData>[]),
        ),
        connectivityStateProvider
            .overrideWith((ref) => Stream.value(ConnectivityState.wifi)),
      ],
      child: const MaterialApp(home: ChatyPage()),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

/// "Nový chat" → pick the mentor.
Future<void> _pickMentor(WidgetTester tester) async {
  await tester.tap(find.text(AppStrings.chatyNewChat));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Dějepisec'));
  await tester.pumpAndSettle();
}

Future<void> _send(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
  await tester.tap(find.byIcon(Icons.send));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('picking a mentor and leaving creates no conversation',
      (tester) async {
    final repo = await _pumpChatTab(tester, const Size(390, 844));

    await _pickMentor(tester);

    expect(find.byType(ChatDetailPage), findsOneWidget);
    final page = tester.widget<ChatDetailPage>(find.byType(ChatDetailPage));
    expect(page.sessionId, isEmpty);
    expect(page.mentorSlug, 'dejepisec');
    expect(repo.createdFor, isEmpty, reason: 'picking a mentor is not a chat');

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.byType(ChatDetailPage), findsNothing);
    expect(repo.createdFor, isEmpty);
  });

  testWidgets('the first message creates the session with the picked mentor',
      (tester) async {
    final repo = await _pumpChatTab(tester, const Size(390, 844));

    await _pickMentor(tester);
    await _send(tester, 'Kdy byla bitva na Bílé hoře?');

    expect(repo.createdFor, ['dejepisec']);
    expect(repo.sentTo, ['s1']);
  });

  testWidgets('a new chat in the wide pane keeps its state through the first '
      'message', (tester) async {
    final repo = await _pumpChatTab(tester, const Size(1280, 900));

    await _pickMentor(tester);

    expect(repo.createdFor, isEmpty);
    final state = tester.state(find.byType(ChatDetailPage));

    await _send(tester, 'Kdy byla bitva na Bílé hoře?');

    expect(repo.createdFor, ['dejepisec']);
    expect(repo.sentTo, ['s1']);
    // The pane now knows its session, and is still the same chat: swapping it
    // would cut off the answer that is streaming in.
    expect(
      tester.widget<ChatDetailPage>(find.byType(ChatDetailPage)).sessionId,
      's1',
    );
    expect(tester.state(find.byType(ChatDetailPage)), same(state));
  });

  testWidgets('opening the new chat from the list keeps the pane',
      (tester) async {
    // The first message puts the chat in the list; a student who clicks it
    // there must not lose the answer that is still streaming in.
    final sessions = StreamController<List<ChatSessionsTableData>>();
    addTearDown(sessions.close);
    // Before pumping: until the list has data its spinner never settles.
    sessions.add(const []);
    final repo = await _pumpChatTab(
      tester,
      const Size(1280, 900),
      sessions: sessions.stream,
    );

    await _pickMentor(tester);
    final state = tester.state(find.byType(ChatDetailPage));
    await _send(tester, 'Kdy byla bitva na Bílé hoře?');

    sessions.add([_listed('s1', 'Bílá hora')]);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bílá hora').first);
    await tester.pumpAndSettle();

    expect(repo.sentTo, ['s1']);
    expect(tester.state(find.byType(ChatDetailPage)), same(state));
    expect(
      tester.widget<ChatDetailPage>(find.byType(ChatDetailPage)).sessionTitle,
      'Bílá hora',
    );
  });
}
