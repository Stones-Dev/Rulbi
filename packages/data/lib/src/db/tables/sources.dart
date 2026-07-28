import 'package:drift/drift.dart';

import 'syncable_columns.dart';

/// Espejo de `Source`/`SourceConfig` de `iptv_core` (T1.6). `configJson`
/// serializa el `SourceConfig` concreto (m3uFile/m3uUrl/xtream) — nunca
/// incluye el secreto de una fuente Xtream, que vive en el almacén
/// seguro de la plataforma (P5), indexado por `id`.
// `SourceRow`, no `Source`: el nombre por defecto de drift para la fila
// de "Sources" colisionaría con la entidad `Source` de iptv_core.
@DataClassName('SourceRow')
@TableIndex(name: 'idx_sources_updated_at', columns: {#updatedAt})
class Sources extends Table with SyncableColumns {
  TextColumn get id => text()();
  TextColumn get kind => text()();
  TextColumn get name => text()();
  TextColumn get configJson => text()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  DateTimeColumn get lastRefresh => dateTime().nullable()();
  TextColumn get refreshPolicy =>
      text().withDefault(const Constant('manual'))();

  @override
  Set<Column> get primaryKey => {id};
}
