// Chaty list without status filters (BR-4JVEEA).
//
// The page showed three chips — Všechny / Probíhající / Ukončené — that only
// stored the tapped index; the list never read it, so every chip showed the
// same conversations. A chat has no "ended" state to filter by (neither the
// local table nor the API keeps one, and nothing in the app ends a chat), so
// the chips are gone and the list is every conversation, newest first as the
// data source returns it.
//
//   flutter test test/widgets/chat_list_no_filter_chips_test.dart
import 'package:eduai/core/connectivity/connectivity_service.dart';
import 'package:eduai/core/database/app_database.dart';
import 'package:eduai/core/providers/core_providers.dart';
import 'package:eduai/core/strings/app_strings.dart';
import 'package:eduai/pages/chaty_page.dart';
import 'package:eduai/widgets/filter_chip_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const Size _phone = Size(390, 844);
const Size _desktop = Size(1440, 900);

/// The test-only Ahem font is far wider than the real one, so labels overflow
/// their rows. Cosmetic and test-only — same suppression the other chat tests
/// use.
void _ignoreOverflow() {
  final oldOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exception.toString().contains('overflowed')) return;
    oldOnError?.call(details);
  };
  addTearDown(() => FlutterError.onError = oldOnError);
}

ChatSessionsTableData _session(String id, String title, DateTime lastAt) {
  return ChatSessionsTableData(
    id: id,
    userId: 'u1',
    title: title,
    persona: 'ai_teacher',
    lastMessageAt: lastAt,
    syncStatus: 'synced',
    createdAt: lastAt,
    updatedAt: lastAt,
  );
}

Future<void> _pump(
  WidgetTester tester,
  Size size,
  List<ChatSessionsTableData> sessions,
) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  _ignoreOverflow();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        chatSessionsStreamProvider.overrideWith((ref) => Stream.value(sessions)),
        connectivityStateProvider.overrideWith(
          (ref) => Stream.value(ConnectivityState.wifi),
        ),
      ],
      child: const MaterialApp(home: ChatyPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final now = DateTime.now();
  final sessions = [
    _session('s1', 'Zlomky', now.subtract(const Duration(minutes: 11))),
    _session('s2', 'Přijímačky', now.subtract(const Duration(days: 40))),
  ];

  for (final entry in {'phone': _phone, 'desktop': _desktop}.entries) {
    testWidgets('no status filter chips on ${entry.key}', (tester) async {
      await _pump(tester, entry.value, sessions);

      expect(find.byType(FilterChipRow), findsNothing);
      expect(find.text(AppStrings.filterInProgress), findsNothing);
      expect(find.text(AppStrings.filterAll), findsNothing);
    });

    testWidgets('every conversation is listed on ${entry.key}',
        (tester) async {
      await _pump(tester, entry.value, sessions);

      // A fresh chat and a long-silent one alike: nothing hides either.
      expect(find.text('Zlomky'), findsOneWidget);
      expect(find.text('Přijímačky'), findsOneWidget);
    });
  }

  testWidgets('the empty state still shows with no conversations',
      (tester) async {
    await _pump(tester, _phone, const []);

    expect(find.byType(FilterChipRow), findsNothing);
    expect(find.text(AppStrings.chatEmptyState), findsOneWidget);
  });
}
