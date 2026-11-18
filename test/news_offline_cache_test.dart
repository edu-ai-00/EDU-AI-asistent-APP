// BR-7XZXZD — offline, Novinky showed no news at all: the repository was
// online-only, so any failed request left the page on its error state. It now
// keeps the last list (and the articles opened from it) for offline.
//
//   flutter test test/news_offline_cache_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eduai/core/network/api_client.dart';
import 'package:eduai/data/datasources/remote/news_remote_datasource.dart';
import 'package:eduai/data/repositories/news_repository.dart';
import 'package:eduai/models/news_model.dart';

NewsItem _item(int id, {bool isRead = false, String? body}) => NewsItem(
      id: id,
      title: 'Novinka $id',
      perex: 'perex $id',
      body: body,
      publishedAt: DateTime.utc(2026, 10, id),
      isRead: isRead,
    );

class _FakeRemote implements NewsRemoteDataSource {
  List<NewsItem> items;
  bool online = true;

  _FakeRemote(this.items);

  @override
  Future<ApiResult<({List<NewsItem> items, int unreadCount})>> getNews() async {
    if (!online) return ApiResult.failure('Connection failed');
    return ApiResult.success((
      items: items,
      unreadCount: items.where((i) => !i.isRead).length,
    ));
  }

  @override
  Future<ApiResult<NewsItem>> getNewsItem(int id) async {
    if (!online) return ApiResult.failure('Connection failed');
    final item = items.firstWhere((i) => i.id == id);
    return ApiResult.success(item.copyWith(body: 'tělo ${item.id}'));
  }

  @override
  Future<ApiResult<int>> markRead(int id) async =>
      ApiResult.failure('not used');
}

void main() {
  late SharedPreferences prefs;
  late _FakeRemote remote;
  late NewsRepository repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    remote = _FakeRemote([_item(1), _item(2, isRead: true), _item(3)]);
    repository = NewsRepository(remote, prefs);
  });

  test('offline: the list from last time, with its unread count', () async {
    await repository.fetchList();

    remote.online = false;
    final offline = await repository.fetchList();

    expect(offline.items.map((i) => i.id), [1, 2, 3]);
    expect(offline.items.map((i) => i.title), ['Novinka 1', 'Novinka 2', 'Novinka 3']);
    expect(offline.items[1].isRead, isTrue);
    expect(offline.items.first.publishedAt, DateTime.utc(2026, 10, 1));
    expect(offline.unreadCount, 2);
  });

  test('offline: the kept list survives an app restart', () async {
    await repository.fetchList();

    remote.online = false;
    final restarted = NewsRepository(remote, prefs);

    expect((await restarted.fetchList()).items, hasLength(3));
  });

  test('offline with nothing kept: the error comes through', () async {
    remote.online = false;

    await expectLater(repository.fetchList(), throwsException);
    await expectLater(repository.fetchDetail(1), throwsException);
  });

  test('offline: an article opened before shows its body', () async {
    await repository.fetchList();
    await repository.fetchDetail(1);

    remote.online = false;
    final article = await repository.fetchDetail(1);

    expect(article.title, 'Novinka 1');
    expect(article.body, 'tělo 1');
  });

  test('offline: an article never opened falls back to its list entry',
      () async {
    await repository.fetchList();

    remote.online = false;
    final article = await repository.fetchDetail(3);

    expect(article.title, 'Novinka 3');
    expect(article.body, isNull, reason: 'the detail page shows the perex');
    expect(article.perex, 'perex 3');
  });

  test('an article that dropped off the feed is not kept', () async {
    await repository.fetchList();
    await repository.fetchDetail(1);

    remote.items = [_item(2), _item(3)];
    await repository.fetchList();

    remote.online = false;
    await expectLater(repository.fetchDetail(1), throwsException);
  });

  test('logout drops the kept news', () async {
    await repository.fetchList();
    await repository.fetchDetail(1);

    await NewsRepository.clearCache(prefs);
    remote.online = false;

    await expectLater(repository.fetchList(), throwsException);
    await expectLater(repository.fetchDetail(1), throwsException);
  });

  test('a corrupt cache is dropped, not thrown', () async {
    await prefs.setString('news_list_cache_v1', '{not json');
    remote.online = false;

    await expectLater(repository.fetchList(), throwsException);
    expect(prefs.getString('news_list_cache_v1'), isNull);
  });
}
