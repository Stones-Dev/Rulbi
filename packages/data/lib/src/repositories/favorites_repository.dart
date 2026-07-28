import 'package:drift/drift.dart';
import 'package:iptv_core/iptv_core.dart';

import '../db/database.dart';

final class DriftFavoritesRepository implements FavoritesRepository {
  DriftFavoritesRepository(this._db);

  final IptvDatabase _db;

  @override
  Future<List<Favorite>> getAll() async {
    final rows = await _db.select(_db.favorites).get();
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
    return _db
        .select(_db.favorites)
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
