// BR-RRSCCK: on the Knihovna tab, tapping the bottom bar's "+" again did
// nothing. The "+" *is* the Knihovna tab, so the tap only re-selected the tab
// already on display — `goToMainTab` saw the same tab and the same URL and
// returned. The reporter expected it to open "Máš kód kurzu?", the dialog the
// page's own "Zadat kód kurzu" button opens.
//
// The shell below is `MainScreen` cut down to what the tap goes through: the
// real `AdaptiveShell` (bottom bar at phone width), the real `KnihovnaPage` as
// tab 2, and `tapMainTab` as the nav callback, which is what
// `MainScreen._onItemTapped` hands the tap to.
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eduai/core/database/app_database.dart';
import 'package:eduai/core/layout/breakpoints.dart';
import 'package:eduai/core/providers/core_providers.dart';
import 'package:eduai/core/providers/navigation_providers.dart';
import 'package:eduai/core/strings/app_strings.dart';
import 'package:eduai/data/repositories/course_repository.dart';
import 'package:eduai/pages/knihovna_page.dart';
import 'package:eduai/routing/tab_routes.dart';
import 'package:eduai/widgets/adaptive_shell.dart';
import 'package:eduai/widgets/custom_bottom_nav.dart';

/// An empty catalogue that never reaches the network.
class _EmptyCatalogue extends Fake implements CourseRepository {
  @override
  Stream<List<Course>> watchAllCourses() => Stream.value(const []);

  @override
  Future<List<Course>> refreshCourses() async => const [];
}

class _Shell extends ConsumerWidget {
  const _Shell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(mainTabIndexProvider);
    return AdaptiveShell(
      selectedIndex: index,
      onItemTapped: (i) => tapMainTab(context, ref, i),
      title: 'EduAI',
      child: index == kLibraryTabIndex
          ? const KnihovnaPage()
          : const SizedBox.shrink(),
    );
  }
}

/// The floating "+" in the middle of the bottom bar.
final Finder _plusButton = find.descendant(
  of: find.byType(CustomBottomNav),
  matching: find.byWidgetPredicate((widget) =>
      widget is SvgPicture &&
      widget.bytesLoader is SvgAssetLoader &&
      (widget.bytesLoader as SvgAssetLoader).assetName ==
          'assets/icons/add.svg'),
);

final Finder _codeDialog = find.widgetWithText(
  AlertDialog,
  AppStrings.libraryCodeTitle,
);

Future<ProviderContainer> _pumpShell(
  WidgetTester tester, {
  required int tab,
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

  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);

  final container = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      courseRepositoryProvider.overrideWithValue(_EmptyCatalogue()),
    ],
  );
  addTearDown(container.dispose);
  container.read(mainTabIndexProvider.notifier).state = tab;

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: _Shell()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('"+" tapped again on the Knihovna tab opens the code dialog',
      (tester) async {
    await _pumpShell(tester, tab: kLibraryTabIndex);
    expect(find.byType(KnihovnaPage), findsOneWidget);
    expect(_codeDialog, findsNothing);

    await tester.tap(_plusButton);
    await tester.pumpAndSettle();

    expect(_codeDialog, findsOneWidget);
  });

  testWidgets('"+" from another tab only opens Knihovna', (tester) async {
    final container = await _pumpShell(tester, tab: 0);

    await tester.tap(_plusButton);
    await tester.pumpAndSettle();

    expect(container.read(mainTabIndexProvider), kLibraryTabIndex);
    expect(find.byType(KnihovnaPage), findsOneWidget);
    expect(_codeDialog, findsNothing);

    // …and the next tap is the one that asks for the code.
    await tester.tap(_plusButton);
    await tester.pumpAndSettle();

    expect(_codeDialog, findsOneWidget);
  });

  testWidgets('a request made before the library opened does not replay',
      (tester) async {
    final container = await _pumpShell(tester, tab: 0);
    container.read(libraryCodeDialogRequestProvider.notifier).state++;

    container.read(mainTabIndexProvider.notifier).state = kLibraryTabIndex;
    await tester.pumpAndSettle();

    expect(find.byType(KnihovnaPage), findsOneWidget);
    expect(_codeDialog, findsNothing);
  });

  test('kLibraryTabIndex is the index of the "+" destination', () {
    expect(mainTabPaths[kLibraryTabIndex], '/library');
  });
}
