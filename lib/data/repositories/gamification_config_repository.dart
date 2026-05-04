import 'dart:convert';

import '../../core/database/app_database.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../../models/gamification_config_model.dart';
import 'package:eduai/core/util/silent_log.dart';

/// Repository for downloading, caching, and serving gamification config.
class GamificationConfigRepository {
  final AppDatabase _db;
  final ApiClient _apiClient;

  GamificationConfigRepository({
    required AppDatabase db,
    required ApiClient apiClient,
  })  : _db = db,
        _apiClient = apiClient;

  /// Get config — returns cached or downloads fresh.
  Future<GamificationConfig?> getConfig() async {
    final cached = await _db.getGamificationConfig();
    if (cached != null && cached.configJson != '{}') {
      return GamificationConfig.fromJsonString(cached.configJson);
    }
    // No cache — try to download
    return refreshConfig();
  }

  /// Force refresh from server. Returns null if download fails.
  Future<GamificationConfig?> refreshConfig() async {
    try {
      final result = await _apiClient.get<Map<String, dynamic>>(
        ApiEndpoints.gamificationConfig,
      );

      if (result.isSuccess && result.data != null) {
        final data = result.data!;
        final config = GamificationConfig.fromJson(data);
        await _db.saveGamificationConfig(
          version: config.version,
          configJson: config.toJsonString(),
        );
        return config;
      }
    } catch (e, st) { silentLog('gamification_config_repository', e, st); }

    // Download failed — return cached if available
    final cached = await _db.getGamificationConfig();
    if (cached != null && cached.configJson != '{}') {
      return GamificationConfig.fromJsonString(cached.configJson);
    }
    return null;
  }

  /// Get cached config version (for staleness checking during sync).
  Future<int> getCachedVersion() async {
    final cached = await _db.getGamificationConfig();
    return cached?.version ?? 0;
  }
}
