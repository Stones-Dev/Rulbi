import 'package:drift/drift.dart';

import 'syncable_columns.dart';

/// Espejo de `WatchState` (`iptv_core`, HU-10). Entidad transferible,
/// misma clave que `Favorites`: `(sourceId, refKey)` sobre `ChannelRef`.
// `WatchStateRow`, por consistencia con el resto de tablas (el nombre
// por defecto de drift aquí ya no colisiona con iptv_core, pero se
// unifica el criterio).
@DataClassName('WatchStateRow')
@TableIndex(name: 'idx_watch_state_updated_at', columns: {#updatedAt})
class WatchState extends Table with SyncableColumns {
  TextColumn get sourceId => text()();
  TextColumn get refKey => text()();
  IntColumn get positionMs => integer().withDefault(const Constant(0))();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {sourceId, refKey};
}
