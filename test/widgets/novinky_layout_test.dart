import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eduai/core/layout/breakpoints.dart';
import 'package:eduai/core/providers/core_providers.dart';
import 'package:eduai/core/providers/navigation_providers.dart';
import 'package:eduai/core/providers/notification_providers.dart';
import 'package:eduai/core/strings/app_strings.dart';
import 'package:eduai/data/repositories/feed_repository.dart';
import 'package:eduai/data/repositories/news_repository.dart';
import 'package:eduai/models/news_model.dart';
import 'package:eduai/pages/news_detail_page.dart';
import 'package:eduai/pages/notification_detail_page.dart';
import 'package:eduai/pages/novinky_page.dart';

import '../notifications/fake_notifications_remote.dart';

// Regression tests for BR-ZT56WM. On desktop the shell's `DesktopTopBar`
// already renders "Novinky", so the page rendering its own copy stacked two
// identical headings — and the feed sat in a 720px column with the rest of the
// monitor empty, because the page had no wide layout at all.
//
// The list now comes from the notification feed (news + notifications,
// NOTIF-4); news rows keep the two-pane behaviour these tests pin.

const _items = [
  _Item(1, 'První novinka'),
  _Item(2, 'Druhá novinka'),
];

class _Item {
  final int id;
  final String title;
  const _Item(this.id, this.title);

  NewsItem toModel({String? body}) => NewsItem(
        id: id,
        title: title,
        perex: 'perex $id',
        body: body,
        publishedAt: DateTime(2026, 8, 24),
        isRead: false,
      );
}

class _FakeNewsRepository implements NewsRepository {
  @override
  Future<NewsItem> fetchDetail(int id) async =>
      _items.firstWhere((i) => i.id == id).toModel(body: 'tělo článku $id');

  @override
  Future<int> markRead(int id) async => 0;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpAt(
  WidgetTester tester,
  double width, {
  List<Map<String, dynamic>> notifications = const [],
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, 900);
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final remote = FakeNotificationsRemote()
    ..feedRows = [
      ...notifications,
      for (final i in _items)
        newsRow(i.id, title: i.title, createdAt: DateTime.utc(2026, 8, 24)),
    ];
  final news = _FakeNewsRepository();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        newsRepositoryProvider.overrideWithValue(news),
        notificationsRemoteDataSourceProvider.overrideWithValue(remote),
        feedRepositoryProvider.overrideWithValue(
          FeedRepository(remote, news, prefs),
        ),
      ],
      child: const MaterialApp(home: Scaffold(body: NovinkyPage())),
    ),
  );
  await tester.pump(); // resolve the feed future
  await tester.pump();
}

void main() {
  testWidgets('desktop drops the page heading — the top bar already has it',
      (tester) async {
    await _pumpAt(tester, 1440);

    expect(find.text(AppStrings.novinkyTitle), findsNothing);
  });

  testWidgets('phone keeps its own heading — there is no top bar there',
      (tester) async {
    await _pumpAt(tester, kCompactMaxWidth - 1);

    expect(find.text(AppStrings.novinkyTitle), findsOneWidget);
  });

  testWidgets('desktop shows the feed and an article pane side by side',
      (tester) async {
    await _pumpAt(tester, 1440);

    // Nothing picked yet: the feed plus a prompt, no article.
    expect(find.text('První novinka'), findsOneWidget);
    expect(find.text(AppStrings.novinkyPickArticle), findsOneWidget);
    expect(find.byType(NewsDetailPage), findsNothing);

    await tester.tap(find.text('První novinka'));
    await tester.pump();
    await tester.pump(); // resolve the detail future

    // The article opens beside the feed rather than covering it.
    expect(find.text('První novinka'), findsNWidgets(2)); // card + heading
    expect(find.text('Druhá novinka'), findsOneWidget);
    expect(find.text(AppStrings.novinkyPickArticle), findsNothing);

    final detail = tester.widget<NewsDetailPage>(find.byType(NewsDetailPage));
    expect(detail.id, 1);
    expect(detail.embedded, isTrue);
  });

  testWidgets('switching articles rebuilds the pane', (tester) async {
    await _pumpAt(tester, 1440);

    await tester.tap(find.text('První novinka'));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Druhá novinka').first);
    await tester.pump();
    await tester.pump();

    // Keyed by id, so the second article replaces the first rather than
    // reusing its already-resolved future.
    expect(tester.widget<NewsDetailPage>(find.byType(NewsDetailPage)).id, 2);
    expect(find.text('tělo článku 2'), findsOneWidget);
  });

  // BR-MCEHBH: a school message links to Novinky itself, so on desktop it has
  // to be read in the pane — following the link went nowhere and left the
  // pane empty.
  testWidgets('desktop reads a notification linking to Novinky in the pane',
      (tester) async {
    await _pumpAt(tester, 1440, notifications: [
      notificationRow('01JM',
          title: 'Dnes je potřeba dokončit test',
          body: 'Projděte si kvíz zde: https://app-stage.edu-ai.eu/pin/654321',
          deepLink: '/news',
          category: 'provoz',
          createdAt: DateTime.utc(2026, 10, 8, 13, 18)),
    ]);

    await tester.tap(find.text('Dnes je potřeba dokončit test'));
    await tester.pump();
    await tester.pump();

    expect(find.text(AppStrings.novinkyPickArticle), findsNothing);
    final detail = tester
        .widget<NotificationDetailPage>(find.byType(NotificationDetailPage));
    expect(detail.embedded, isTrue);
    expect(detail.item.id, '01JM');
    // Card + pane heading; the feed stays beside it.
    expect(find.text('Dnes je potřeba dokončit test'), findsNWidgets(2));
    expect(find.text('První novinka'), findsOneWidget);

    // Picking an article afterwards swaps the pane over.
    await tester.tap(find.text('První novinka'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(NotificationDetailPage), findsNothing);
    expect(tester.widget<NewsDetailPage>(find.byType(NewsDetailPage)).id, 1);
  });

  testWidgets('desktop: a notification with a target elsewhere still goes there',
      (tester) async {
    await _pumpAt(tester, 1440, notifications: [
      notificationRow('01JC',
          title: 'Kurz dokončen',
          deepLink: '/courses',
          createdAt: DateTime.utc(2026, 10, 8, 13, 18)),
    ]);

    await tester.tap(find.text('Kurz dokončen'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(NotificationDetailPage), findsNothing);
    expect(find.text(AppStrings.novinkyPickArticle), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(NovinkyPage)),
    );
    expect(container.read(mainTabIndexProvider), 3); // Kurzy
  });

  testWidgets('phone opens an article as a route, not a pane', (tester) async {
    await _pumpAt(tester, kCompactMaxWidth - 1);

    await tester.tap(find.text('První novinka'));
    await tester.pumpAndSettle();

    final detail = tester.widget<NewsDetailPage>(find.byType(NewsDetailPage));
    expect(detail.embedded, isFalse);
    // The pushed route covers the feed.
    expect(find.text('Druhá novinka'), findsNothing);
  });
}
