import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:iptv_core/iptv_core.dart';

import '../db/database.dart';
import '../db/source_config_codec.dart';

final class DriftSourceRepository implements SourceRepository {
  DriftSourceRepository(this._db);

  final IptvDatabase _db;

  @override
  Future<List<Source>> getAll() async {
    final rows = await _db.select(_db.sources).get();
    return rows.map(_toEntity).toList();
  }

  @override
  Future<Source?> getById(String id) async {
    final row = await (_db.select(
      _db.sources,
    )..where((s) => s.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toEntity(row);
  }

  @override
  Future<void> upsert(Source source) {
    return _db.into(_db.sources).insertOnConflictUpdate(_toCompanion(source));
  }

  @override
  Stream<List<Source>> watchAll() {
    return _db
        .select(_db.sources)
        .watch()
        .map((rows) => rows.map(_toEntity).toList());
  }

  Source _toEntity(SourceRow row) => Source(
    id: row.id,
    name: row.name,
    config: sourceConfigFromJson(
      row.kind,
      jsonDecode(row.configJson) as Map<String, Object?>,
    ),
    enabled: row.enabled,
    lastRefresh: row.lastRefresh,
    refreshPolicy: SourceRefreshPolicy.values.byName(row.refreshPolicy),
    updatedAt: row.updatedAt,
    deletedAt: row.deletedAt,
  );

  SourcesCompanion _toCompanion(Source source) => SourcesCompanion.insert(
    id: source.id,
    kind: source.kind.name,
    name: source.name,
    configJson: jsonEncode(sourceConfigToJson(source.config)),
    enabled: Value(source.enabled),
    lastRefresh: Value(source.lastRefresh),
    refreshPolicy: Value(source.refreshPolicy.name),
    updatedAt: Value(source.updatedAt),
    deletedAt: Value(source.deletedAt),
  );
}
