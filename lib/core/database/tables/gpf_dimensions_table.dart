import 'package:drift/drift.dart';

/// Drift table caching the canonical GPF vector dimension labels.
///
/// Source of truth is the backend `VectorDimension` set (endpoint
/// `GET /api/gpf/dimensions`). Cached locally so the skills view renders Czech
/// labels offline. Seeded on first run from the bundled
/// `assets/gpf/dimensions_cs.json` asset, then refreshed on sync.
class GpfDimensionsTable extends Table {
  @override
  String get tableName => 'gpf_dimensions';

  /// Zero-based index in the 35-element vector (0–34). Primary key.
  IntColumn get dimensionIndex => integer()();

  /// Hierarchical code, e.g. "N1.1".
  TextColumn get code => text()();

  /// Parent domain code, e.g. "N".
  TextColumn get domainCode => text()();

  /// Czech domain name, e.g. "Číslo a operace".
  TextColumn get domainName => text()();

  /// Czech construct name, e.g. "Přirozená čísla".
  TextColumn get constructName => text()();

  /// Czech subconstruct name.
  TextColumn get name => text()();

  @override
  Set<Column> get primaryKey => {dimensionIndex};
}
