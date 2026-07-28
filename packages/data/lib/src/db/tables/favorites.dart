import 'package:drift/drift.dart';

import 'syncable_columns.dart';

/// Espejo de `Favorite` (`iptv_core`, HU-05). Entidad transferible:
/// clave primaria `(sourceId, refKey)` sobre `ChannelRef`, nunca sobre
/// el `id` de `Channels`.
// `FavoriteRow`, no `Favorite`: evita colisión con la entidad
// `Favorite` de iptv_core.
@DataClassName('FavoriteRow')
@TableIndex(name: 'idx_favorites_updated_at', columns: {#updatedAt})
class Favorites extends Table with SyncableColumns {
  TextColumn get sourceId => text()();
  TextColumn get refKey => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {sourceId, refKey};
}
