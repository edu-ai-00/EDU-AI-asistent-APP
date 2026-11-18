import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/dashboard_banner.dart';
import '../datasources/remote/dashboard_banners_remote_datasource.dart';

/// Repository for the dashboard's admin-managed banners (BR-SAWX2U).
///
/// The banners replace copy that used to ship inside the app build, so the
/// dashboard must never lose them to a dropped connection: the last good
/// answer is cached and served when the fetch fails. An empty cache means an
/// empty strip, which is the same thing the dashboard showed before a banner
/// existed — never an error the learner has to deal with.
///
/// The cache holds the server's conditions as delivered, not a decision about
/// them: the XP band is evaluated per build against the device's own XP.
class DashboardBannersRepository {
  static const String _cacheKey = 'dashboard_banners_cache_v1';

  final DashboardBannersRemoteDataSource _remoteDataSource;
  final SharedPreferences _prefs;

  DashboardBannersRepository(this._remoteDataSource, this._prefs);

  /// Fetch the banners, falling back to the cache when offline.
  Future<List<DashboardBanner>> fetchBanners() async {
    final result = await _remoteDataSource.getBanners();

    if (result.isFailure) {
      return _readCache();
    }

    _writeCache(result.data!);
    return result.data!;
  }

  /// Drop the cache — the banners a signed-out account qualified for are not
  /// the next account's.
  static Future<void> clearCache(SharedPreferences prefs) =>
      prefs.remove(_cacheKey);

  List<DashboardBanner> _readCache() {
    final raw = _prefs.getString(_cacheKey);
    if (raw == null) return const [];

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((json) => DashboardBanner.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // A cache written by an older schema is not worth recovering.
      _prefs.remove(_cacheKey);
      return const [];
    }
  }

  void _writeCache(List<DashboardBanner> banners) {
    _prefs.setString(
      _cacheKey,
      jsonEncode(banners.map((banner) => banner.toJson()).toList()),
    );
  }
}
