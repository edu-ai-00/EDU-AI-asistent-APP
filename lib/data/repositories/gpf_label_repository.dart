import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../core/database/app_database.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/util/silent_log.dart';

/// One canonical GPF vector dimension label.
class GpfDimensionLabel {
  final int dimensionIndex;
  final String code;
  final String domainCode;
  final String domainName;
  final String constructName;
  final String name;

  const GpfDimensionLabel({
    required this.dimensionIndex,
    required this.code,
    required this.domainCode,
    required this.domainName,
    required this.constructName,
    required this.name,
  });

  factory GpfDimensionLabel.fromJson(Map<String, dynamic> json) {
    return GpfDimensionLabel(
      dimensionIndex: (json['dimension_index'] as num).toInt(),
      code: json['code'] as String,
      domainCode: json['domain_code'] as String,
      domainName: json['domain_name'] as String,
      constructName: json['construct_name'] as String? ?? '',
      name: json['name'] as String? ?? '',
    );
  }
}

/// Resolves GPF dimension labels (Czech) for the skills view.
///
/// Canonical source is the backend (`GET /api/gpf/dimensions`). Labels are
/// cached in Drift and, on first run / offline, seeded from the bundled
/// `assets/gpf/dimensions_cs.json` so the skills card never shows English or a
/// blank title.
class GpfLabelRepository {
  GpfLabelRepository(this._db, this._api);

  final AppDatabase _db;
  final ApiClient _api;

  static const String _assetPath = 'assets/gpf/dimensions_cs.json';

  /// Return all labels, Drift-first, falling back to the bundled asset.
  ///
  /// If the Drift cache is empty (fresh install, never synced) it is seeded
  /// from the bundled asset so subsequent reads are fast and consistent.
  Future<List<GpfDimensionLabel>> getLabels() async {
    final cached = await _db.getGpfDimensions();
    if (cached.isNotEmpty) {
      return cached.map(_fromRow).toList();
    }

    final bundled = await _loadBundled();
    if (bundled.isNotEmpty) {
      await _save(bundled);
    }
    return bundled;
  }

  /// Map of domain code → Czech domain name (e.g. "N" → "Číslo a operace").
  Future<Map<String, String>> domainNames() async {
    final labels = await getLabels();
    final map = <String, String>{};
    for (final l in labels) {
      map.putIfAbsent(l.domainCode, () => l.domainName);
    }
    return map;
  }

  /// Fetch the canonical labels from the backend and replace the cache.
  ///
  /// Non-fatal on failure — the cache / bundled asset keeps serving.
  Future<void> refreshFromServer() async {
    try {
      final result =
          await _api.get<Map<String, dynamic>>(ApiEndpoints.gpfDimensions);
      if (!result.isSuccess || result.data == null) return;

      final rows = (result.data!['data'] as List<dynamic>?) ?? const [];
      if (rows.isEmpty) return;

      final labels = rows
          .map((e) => GpfDimensionLabel.fromJson(e as Map<String, dynamic>))
          .toList();
      await _save(labels);
    } catch (e, st) {
      silentLog('gpf_label_repository', e, st);
    }
  }

  Future<List<GpfDimensionLabel>> _loadBundled() async {
    try {
      final raw = await rootBundle.loadString(_assetPath);
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => GpfDimensionLabel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      silentLog('gpf_label_repository', e, st);
      return const [];
    }
  }

  Future<void> _save(List<GpfDimensionLabel> labels) {
    final rows = labels
        .map((l) => GpfDimensionsTableCompanion.insert(
              dimensionIndex: Value(l.dimensionIndex),
              code: l.code,
              domainCode: l.domainCode,
              domainName: l.domainName,
              constructName: l.constructName,
              name: l.name,
            ))
        .toList();
    return _db.replaceGpfDimensions(rows);
  }

  GpfDimensionLabel _fromRow(GpfDimensionsTableData r) => GpfDimensionLabel(
        dimensionIndex: r.dimensionIndex,
        code: r.code,
        domainCode: r.domainCode,
        domainName: r.domainName,
        constructName: r.constructName,
        name: r.name,
      );
}
