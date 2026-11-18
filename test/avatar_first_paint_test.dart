// How fast the avatar catalog reaches the screen (BR-VCD7JD).
//
// Reported against the onboarding's "Vyber si vibe" step, which sat empty for
// several seconds. The artwork is not heavy — forty items of about 5 KB — but
// it was fetched one item after another, so the wait was the *sum* of forty
// round trips, and the whole screen blocked on it. These tests pin the two
// halves of the fix: the downloads overlap, and a device that already has the
// catalog paints from it instead of waiting for the network at all.
//
// Run:
//   flutter test test/avatar_first_paint_test.dart
import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eduai/core/database/app_database.dart';
import 'package:eduai/core/network/api_client.dart';
import 'package:eduai/core/providers/core_providers.dart';
import 'package:eduai/core/sync/sync_queue.dart';
import 'package:eduai/core/sync/sync_status.dart';
import 'package:eduai/data/datasources/remote/avatar_remote_datasource.dart';
import 'package:eduai/data/repositories/avatar_repository.dart';
import 'package:eduai/models/avatar_model.dart';

const _userId = 'user-1';

const _svg = '<svg xmlns="http://www.w3.org/2000/svg" '
    'viewBox="0 0 270.93 270.93">'
    '<rect x="67" y="67" width="136" height="136" fill="#000"/></svg>';

AvatarItem _item(String code, {bool isDefault = false}) => AvatarItem(
      code: code,
      name: code,
      slot: AvatarSlot.head,
      layer: 40,
      url: 'https://r2.test/$code.svg',
      rarity: AvatarRarity.common,
      price: 0,
      isDefault: isDefault,
      owned: false,
    );

/// A bucket that takes its time and keeps score of how many downloads are in
/// flight at once — the one thing a serial loop can never make go above 1.
class _CountingRemote implements AvatarRemoteDataSource {
  final List<AvatarItem> catalog;
  final Duration latency;

  int inFlight = 0;
  int peakInFlight = 0;
  int downloads = 0;

  _CountingRemote(this.catalog, {this.latency = const Duration(milliseconds: 20)});

  @override
  Future<ApiResult<List<AvatarItem>>> getCatalog() async =>
      ApiResult.success(catalog);

  @override
  Future<ApiResult<String>> downloadSvg(String url) async {
    downloads++;
    inFlight++;
    if (inFlight > peakInFlight) peakInFlight = inFlight;
    try {
      await Future<void>.delayed(latency);
      return ApiResult.success(_svg);
    } finally {
      inFlight--;
    }
  }

  @override
  Future<ApiResult<RemoteUserAvatar>> getUserAvatar() async =>
      ApiResult.success(const RemoteUserAvatar(equipped: {}, ownedCodes: {}));

  @override
  Future<ApiResult<RemoteUserAvatar>> purchase(String code) async =>
      ApiResult.failure('not used');

  @override
  Future<ApiResult<RemoteUserAvatar>> updateEquipped(
    Map<String, String> equipped,
  ) async =>
      ApiResult.failure('not used');
}

/// A bucket that never answers — stands in for the seconds the fetch takes on
/// a real connection.
class _HangingRemote implements AvatarRemoteDataSource {
  final _never = Completer<ApiResult<List<AvatarItem>>>();

  @override
  Future<ApiResult<List<AvatarItem>>> getCatalog() => _never.future;

  @override
  Future<ApiResult<String>> downloadSvg(String url) async =>
      ApiResult.failure('unreachable');

  @override
  Future<ApiResult<RemoteUserAvatar>> getUserAvatar() async =>
      ApiResult.failure('unreachable');

  @override
  Future<ApiResult<RemoteUserAvatar>> purchase(String code) async =>
      ApiResult.failure('unreachable');

  @override
  Future<ApiResult<RemoteUserAvatar>> updateEquipped(
    Map<String, String> equipped,
  ) async =>
      ApiResult.failure('unreachable');
}

/// An API that answers only when the test says so — the catalog fetch of a
/// first run that takes longer than the screen is willing to wait.
class _GatedRemote extends _CountingRemote {
  final gate = Completer<void>();

  _GatedRemote(super.catalog);

  @override
  Future<ApiResult<List<AvatarItem>>> getCatalog() async {
    await gate.future;
    return super.getCatalog();
  }
}

Future<void> _activateUser(AppDatabase db) => db.createAndActivateUser(
      const UsersTableCompanion(
        id: Value(_userId),
        email: Value('a@b.test'),
        name: Value('Tester'),
        isActive: Value(true),
      ),
    );

/// A catalog already on the device, artwork and all.
Future<void> _seedCachedCatalog(AppDatabase db) async {
  await db.upsertAvatarItem(
    const AvatarItemsTableCompanion(
      code: Value('head_crown'),
      name: Value('head_crown'),
      slot: Value('head'),
      layer: Value(40),
      url: Value('https://r2.test/head_crown.svg'),
      rarity: Value('common'),
      price: Value(0),
      isDefault: Value(false),
      svgSource: Value(_svg),
    ),
  );

  await db.upsertUserAvatar(
    UserAvatarTableCompanion(
      userId: const Value(_userId),
      equipped: const Value('{}'),
      ownedCodes: Value(jsonEncode(const ['head_crown'])),
      syncStatus: Value(SyncStatus.synced.toInt()),
    ),
  );
}

void main() {
  // The repository reads the bundled starting outfit through `rootBundle`.
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  test('artwork downloads overlap instead of queueing up one by one', () async {
    final remote = _CountingRemote([for (var i = 0; i < 20; i++) _item('item_$i')]);
    final repo = AvatarRepository(remote, db, SyncQueue(db));

    final started = DateTime.now();
    expect(await repo.refresh(_userId), isTrue);
    final elapsed = DateTime.now().difference(started);

    expect(remote.downloads, 20, reason: 'every item still gets fetched');
    expect(
      remote.peakInFlight,
      greaterThan(1),
      reason: 'serial downloads made a first launch wait for 40 round trips',
    );
    expect(
      elapsed,
      lessThan(const Duration(milliseconds: 20 * 20)),
      reason: 'the wait must be a few waves, not the sum of every latency',
    );
  });

  test('a slow bucket cannot stall the whole catalog behind one item',
      () async {
    // One item on a dead-slow connection used to hold every item after it.
    final remote = _CountingRemote(
      [for (var i = 0; i < 8; i++) _item('item_$i')],
      latency: const Duration(milliseconds: 60),
    );
    final repo = AvatarRepository(remote, db, SyncQueue(db));

    final started = DateTime.now();
    await repo.refresh(_userId);
    final elapsed = DateTime.now().difference(started);

    expect(
      elapsed,
      lessThan(const Duration(milliseconds: 60 * 8)),
      reason: 'eight items at 60 ms apiece must not cost 480 ms',
    );
  });

  test('a cached catalog paints before the network answers', () async {
    // The reported symptom: the vibe step showed nothing until the refresh
    // finished. With artwork already on the device there is nothing to wait
    // for — the fetch may keep running, the screen must not.
    await db.createAndActivateUser(
      const UsersTableCompanion(
        id: Value(_userId),
        email: Value('a@b.test'),
        name: Value('Tester'),
        isActive: Value(true),
      ),
    );
    await _seedCachedCatalog(db);

    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        avatarRemoteDataSourceProvider.overrideWithValue(_HangingRemote()),
      ],
    );
    addTearDown(container.dispose);

    final state = await container
        .read(avatarControllerProvider.future)
        .timeout(const Duration(seconds: 2));

    expect(
      state.byCode['head_crown']?.isDrawable,
      isTrue,
      reason: 'the cached artwork is what the step draws while the fetch runs',
    );
  });

  // BR-QFW7WF: with the API down, every request sat ~15 s on a 502 from the
  // proxy and was then retried once, so a first run — nothing cached, so the
  // shop waits for the network — showed its spinner for half a minute and
  // more, which reads as loading forever.
  group('a first run with no cached catalog', () {
    test('stops waiting for a catalog that never comes', () async {
      await _activateUser(db);

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          avatarRemoteDataSourceProvider.overrideWithValue(_HangingRemote()),
          avatarFirstLoadTimeoutProvider
              .overrideWithValue(const Duration(milliseconds: 50)),
        ],
      );
      addTearDown(container.dispose);

      final state = await container
          .read(avatarControllerProvider.future)
          .timeout(const Duration(seconds: 2));

      expect(state.fromCache, isTrue,
          reason: 'the shop must be able to tell the catalog never arrived');
      expect(state.catalog.where((i) => !i.isDefault), isEmpty);
      expect(
        state.equippedLayers,
        isNotEmpty,
        reason: 'the bundled starting outfit still gives the avatar a face',
      );
    });

    test('still shows the catalog once a slow fetch lands', () async {
      await _activateUser(db);

      final remote = _GatedRemote([_item('head_crown')]);
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          avatarRemoteDataSourceProvider.overrideWithValue(remote),
          avatarFirstLoadTimeoutProvider
              .overrideWithValue(const Duration(milliseconds: 50)),
        ],
      );
      addTearDown(container.dispose);

      final first = await container
          .read(avatarControllerProvider.future)
          .timeout(const Duration(seconds: 2));
      expect(first.byCode['head_crown'], isNull);

      final landed = Completer<AvatarState>();
      container.listen<AsyncValue<AvatarState>>(avatarControllerProvider,
          (_, next) {
        final value = next.valueOrNull;
        if (value != null && value.byCode.containsKey('head_crown')) {
          if (!landed.isCompleted) landed.complete(value);
        }
      });

      remote.gate.complete();
      final state = await landed.future.timeout(const Duration(seconds: 2));

      expect(state.fromCache, isFalse);
      expect(state.byCode['head_crown']?.isDrawable, isTrue);
    });
  });
}
