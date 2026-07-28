import 'package:drift/drift.dart';
import 'package:iptv_core/iptv_core.dart';

import '../db/database.dart';

final class DriftWatchStateRepository implements WatchStateRepository {
  DriftWatchStateRepository(this._db);

  final IptvDatabase _db;

  @override
  Future<List<WatchState>> getAll() async {
    final rows = await _db.select(_db.watchState).get();
    return rows.map(_toEntity).toList();
  }

  @override
  Future<WatchState?> find(ChannelRef channel) async {
    final row =
        await (_db.select(_db.watchState)..where(
              (w) =>
                  w.sourceId.equals(channel.sourceId) &
                  w.refKey.equals(channel.key),
            ))
            .getSingleOrNull();
    return row == null ? null : _toEntity(row);
  }

  @override
  Future<void> upsert(WatchState state) {
    return _db.into(_db.watchState).insertOnConflictUpdate(_toCompanion(state));
  }

  WatchState _toEntity(WatchStateRow row) => WatchState(
    channel: ChannelRef(sourceId: row.sourceId, key: row.refKey),
    position: Duration(milliseconds: row.positionMs),
    duration: Duration(milliseconds: row.durationMs),
    updatedAt: row.updatedAt,
    deletedAt: row.deletedAt,
  );

  WatchStateCompanion _toCompanion(WatchState state) =>
      WatchStateCompanion.insert(
        sourceId: state.channel.sourceId,
        refKey: state.channel.key,
        positionMs: Value(state.position.inMilliseconds),
        durationMs: Value(state.duration.inMilliseconds),
        updatedAt: Value(state.updatedAt),
        deletedAt: Value(state.deletedAt),
      );
}
