import 'package:drift/drift.dart';
import 'package:iptv_core/iptv_core.dart';

import '../db/database.dart';

final class DriftFavoritesRepository implements FavoritesRepository {
  DriftFavoritesRepository(this._db);

  final IptvDatabase _db;

  /// `ORDER BY sort_order, source_id, ref_key` (S5 · Ola 2): el orden
  /// manual del usuario es el punto de la pantalla de Favoritos — sin
  /// esto, la lista se pintaría en el orden físico de la tabla, que no
  /// tiene por qué coincidir con `sortOrder` tras un `reorder`. Los
  /// tombstones (`deletedAt` no nulo) se filtran en el provider de la app,
  /// no aquí — mismo precedente que `sourcesStreamProvider`.
  @override
  Future<List<Favorite>> getAll() async {
    final rows = await (_db.select(_db.favorites)..orderBy([
          (f) => OrderingTerm.asc(f.sortOrder),
          (f) => OrderingTerm.asc(f.sourceId),
          (f) => OrderingTerm.asc(f.refKey),
        ]))
        .get();
    return rows.map(_toEntity).toList();
  }

  @override
  Future<Favorite?> find(ChannelRef channel) async {
    final row =
        await (_db.select(_db.favorites)..where(
              (f) =>
                  f.sourceId.equals(channel.sourceId) &
                  f.refKey.equals(channel.key),
            ))
            .getSingleOrNull();
    return row == null ? null : _toEntity(row);
  }

  @override
  Future<void> upsert(Favorite favorite) {
    return _db
        .into(_db.favorites)
        .insertOnConflictUpdate(_toCompanion(favorite));
  }

  @override
  Stream<List<Favorite>> watchAll() {
    return (_db.select(_db.favorites)..orderBy([
          (f) => OrderingTerm.asc(f.sortOrder),
          (f) => OrderingTerm.asc(f.sourceId),
          (f) => OrderingTerm.asc(f.refKey),
        ]))
        .watch()
        .map((rows) => rows.map(_toEntity).toList());
  }

  Favorite _toEntity(FavoriteRow row) => Favorite(
    channel: ChannelRef(sourceId: row.sourceId, key: row.refKey),
    order: row.sortOrder,
    updatedAt: row.updatedAt,
    deletedAt: row.deletedAt,
  );

  FavoritesCompanion _toCompanion(Favorite favorite) =>
      FavoritesCompanion.insert(
        sourceId: favorite.channel.sourceId,
        refKey: favorite.channel.key,
        sortOrder: Value(favorite.order),
        updatedAt: Value(favorite.updatedAt),
        deletedAt: Value(favorite.deletedAt),
      );
}
