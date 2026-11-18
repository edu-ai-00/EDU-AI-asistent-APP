// BR-KDKQBR — on an iPhone the keyboard stayed up over the chat list after the
// student left a conversation, covering the bottom navigation; only killing
// the app got rid of it.
//
// On iOS 26 UIKit resigns Flutter's text view when the student switches apps,
// the engine reports the connection closed and the composer unfocuses — but
// the engine keeps its client, and UIKit brings the keyboard back for it
// (flutter/flutter#189051, #189263). Nothing the framework does afterwards
// reaches the engine, so the keyboard is stranded.
//
// TestTextInput models the engine side: `closeConnection()` sends the
// platform's TextInputClient.onConnectionClosed and leaves the fake keyboard
// up with its client, exactly the state the engine is left in.
//
//   flutter test test/widgets/chat_keyboard_dismiss_test.dart
import 'package:eduai/core/connectivity/connectivity_service.dart';
import 'package:eduai/core/database/app_database.dart';
import 'package:eduai/core/providers/core_providers.dart';
import 'package:eduai/core/ui/stranded_keyboard_guard.dart';
import 'package:eduai/data/repositories/chat_repository.dart';
import 'package:eduai/pages/chat_detail_page.dart';
import 'package:eduai/pages/chaty_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _iOS = TargetPlatformVariant.only(TargetPlatform.iOS);

/// Height of the keyboard the fake view reports, in logical pixels.
const _keyboard = FakeViewPadding(bottom: 300);

class _FakeChatRepo implements ChatRepository {
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

ChatSessionsTableData _session() {
  final now = DateTime(2026, 11, 13, 21, 0);
  return ChatSessionsTableData(
    id: 's1',
    userId: 'u1',
    serverId: 42,
    title: 'Bílá hora',
    persona: 'ai_teacher',
    lastMessageAt: now,
    syncStatus: 'synced',
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

/// The chat tab on a phone, with a conversation open and the composer tapped.
Future<void> _openChatAndType(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.reset);
  _ignoreOverflow();

  await tester.pumpWidget(
    StrandedKeyboardGuard(
      child: ProviderScope(
        overrides: [
          chatRepositoryProvider.overrideWithValue(_FakeChatRepo()),
          activeUserProvider.overrideWith((ref) async => _user()),
          chatSessionsStreamProvider.overrideWith(
            (ref) => Stream.value([_session()]),
          ),
          chatMessagesStreamProvider.overrideWith(
            (ref, sessionId) => Stream.value(const <ChatMessagesTableData>[]),
          ),
          connectivityStateProvider.overrideWith(
            (ref) => Stream.value(ConnectivityState.wifi),
          ),
        ],
        child: const MaterialApp(home: ChatyPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.text('Bílá hora'));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(TextField));
  await tester.pump();
  tester.view.viewInsets = _keyboard;
  await tester.pump();

  expect(_composerHasFocus(), isTrue);
  expect(tester.testTextInput.isVisible, isTrue);
}

bool _composerHasFocus() {
  final context = FocusManager.instance.primaryFocus?.context;
  return context?.findAncestorStateOfType<EditableTextState>() != null;
}

List<String> _sent(WidgetTester tester) =>
    tester.testTextInput.log.map((call) => call.method).toList();

/// iOS takes the text view away: the app went to the background, say.
Future<void> _platformClosesConnection(WidgetTester tester) async {
  tester.testTextInput.closeConnection();
  await tester.pump();
  expect(
    _composerHasFocus(),
    isFalse,
    reason: 'the framework lets go of the field on a platform close',
  );
}

void main() {
  testWidgets('the keyboard iOS brings back after an app switch is hidden', (
    tester,
  ) async {
    await _openChatAndType(tester);

    // Backgrounded: the keyboard is gone from the screen, the engine still
    // holds the composer's client.
    tester.view.viewInsets = FakeViewPadding.zero;
    await _platformClosesConnection(tester);
    tester.testTextInput.log.clear();

    // Back in the app, UIKit makes the stale text view first responder again.
    tester.view.viewInsets = _keyboard;
    await tester.pump();

    expect(_sent(tester), ['TextInput.clearClient', 'TextInput.hide']);
    expect(tester.testTextInput.isVisible, isFalse);
  }, variant: _iOS);

  testWidgets('leaving the chat does not leave the keyboard over the list', (
    tester,
  ) async {
    await _openChatAndType(tester);

    // Closed by the platform while the keyboard stays on screen.
    await _platformClosesConnection(tester);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.byType(ChatDetailPage), findsNothing);
    expect(
      tester.testTextInput.isVisible,
      isFalse,
      reason: 'nothing on the chat list can take the keyboard down',
    );
  }, variant: _iOS);

  testWidgets('a focused field keeps its keyboard', (tester) async {
    await _openChatAndType(tester);
    tester.testTextInput.log.clear();

    // The keyboard growing (suggestions bar, a taller layout) while the
    // student types.
    tester.view.viewInsets = const FakeViewPadding(bottom: 340);
    await tester.pump();

    expect(_sent(tester), isNot(contains('TextInput.hide')));
    expect(_sent(tester), isNot(contains('TextInput.clearClient')));
    expect(tester.testTextInput.isVisible, isTrue);
  }, variant: _iOS);

  testWidgets('Android is left alone', (tester) async {
    // UIKit's resign-and-restore is iOS behaviour; Android's IME follows the
    // framework.
    await _openChatAndType(tester);
    tester.view.viewInsets = FakeViewPadding.zero;
    await _platformClosesConnection(tester);
    tester.testTextInput.log.clear();

    tester.view.viewInsets = _keyboard;
    await tester.pump();

    expect(_sent(tester), isEmpty);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
