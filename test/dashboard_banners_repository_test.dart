// BR-SAWX2U: the dashboard banners used to ship inside the app build, so the
// strip must not vanish the moment a fetch fails — the last good answer is
// cached and served instead.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eduai/core/network/api_client.dart';
import 'package:eduai/core/services/auth_token_storage.dart';
import 'package:eduai/data/datasources/remote/dashboard_banners_remote_datasource.dart';
import 'package:eduai/data/repositories/dashboard_banners_repository.dart';
import 'package:eduai/models/dashboard_banner.dart';

/// Answers whatever [next] holds; null stands for a failed request.
class _FakeRemote extends DashboardBannersRemoteDataSource {
  _FakeRemote(super.apiClient);

  List<DashboardBanner>? next;

  @override
  Future<ApiResult<List<DashboardBanner>>> getBanners() async {
    final banners = next;
    return banners == null
        ? ApiResult.failure('offline')
        : ApiResult.success(banners);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late _FakeRemote remote;
  late DashboardBannersRepository repo;

  const server = [
    DashboardBanner(
      id: 1,
      key: 'system.jpz_intro',
      badge: 'PŘIJÍMAČKY',
      title: 'Uvažuješ o přijímačkách?',
      body: 'Projdi si úvod',
      link: '/field-course/EDU_JPZ_INTRO',
      maxXp: 100,
    ),
  ];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    remote = _FakeRemote(ApiClient(AuthTokenStorage(prefs: prefs)));
    repo = DashboardBannersRepository(remote, prefs);
  });

  test('a successful fetch is cached and served again when offline', () async {
    remote.next = server;
    expect((await repo.fetchBanners()).single.key, 'system.jpz_intro');

    remote.next = null;
    final offline = await repo.fetchBanners();

    expect(offline, hasLength(1));
    expect(offline.single.title, 'Uvažuješ o přijímačkách?');
    // The conditions are cached as delivered, so the band still applies.
    expect(offline.single.maxXp, 100);
    expect(offline.single.appliesTo(100), isTrue);
    expect(offline.single.appliesTo(101), isFalse);
  });

  test('a failed fetch with nothing cached is an empty strip, not a throw',
      () async {
    remote.next = null;

    expect(await repo.fetchBanners(), isEmpty);
  });

  test('the cache follows the server when a banner is switched off', () async {
    remote.next = server;
    await repo.fetchBanners();

    remote.next = const [];
    expect(await repo.fetchBanners(), isEmpty);

    // And the emptied cache is what a later offline read sees.
    remote.next = null;
    expect(await repo.fetchBanners(), isEmpty);
  });

  test('signing out drops the cache', () async {
    remote.next = server;
    await repo.fetchBanners();

    await DashboardBannersRepository.clearCache(prefs);

    remote.next = null;
    expect(await repo.fetchBanners(), isEmpty);
  });

  test('a cache written by an older schema is discarded, not crashed on',
      () async {
    await prefs.setString('dashboard_banners_cache_v1', '{"not":"a list"}');
    remote.next = null;

    expect(await repo.fetchBanners(), isEmpty);
    expect(prefs.getString('dashboard_banners_cache_v1'), isNull);
  });
}
