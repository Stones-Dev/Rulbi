import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:iptv_core/iptv_core.dart';

import '../db/database.dart';

/// Implementa `ChannelRepository` y `ChannelSearchPort` (T1.6) sobre el
/// esquema de `channels`/`categories`/el índice FTS5 (T1.5).
final class DriftChannelRepository
    implements ChannelRepository, ChannelSearchPort {
  DriftChannelRepository(this._db);

  final IptvDatabase _db;

  @override
  Future<void> replaceSourceContent(
    String sourceId,
    Stream<Channel> channels,
  ) async {
    await _db.transaction(() async {
      await (_db.delete(
        _db.channels,
      )..where((c) => c.sourceId.equals(sourceId))).go();

      await for (final channel in channels) {
        await _db.into(_db.channels).insert(_toCompanion(channel));
      }
    });
  }

  @override
  Future<List<Category>> categoriesFor(String sourceId) async {
    final rows = await (_db.select(
      _db.categories,
    )..where((c) => c.sourceId.equals(sourceId))).get();
    return rows.map(_categoryToEntity).toList();
  }

  @override
  Stream<List<Channel>> watchChannels({required String categoryId}) {
    return (_db.select(_db.channels)
          ..where((c) => c.categoryId.equals(categoryId)))
        .watch()
        .map((rows) => rows.map(_channelToEntity).toList());
  }

  /// RNF-01: percibido < 100 ms sobre 100k canales. `channels_fts` es
  /// una tabla "external content" (T1.5): la consulta hace `JOIN` con
  /// `channels` por `rowid`/`id` para recuperar la fila completa.
  @override
  Future<List<Channel>> search(String query, {int limit = 50}) async {
    final rows = await _db
        .customSelect(
          'SELECT c.* FROM channels_fts f '
          'JOIN channels c ON c.id = f.rowid '
          'WHERE channels_fts MATCH ? '
          'LIMIT ?',
          variables: [Variable<String>(query), Variable<int>(limit)],
          readsFrom: {_db.channels},
        )
        .get();

    return rows
        .map((row) => _channelToEntity(_db.channels.map(row.data)))
        .toList();
  }

  Channel _channelToEntity(ChannelRow row) => Channel(
    ref: ChannelRef(sourceId: row.sourceId, key: row.refKey),
    sourceId: row.sourceId,
    categoryId: row.categoryId,
    type: ContentType.values.byName(row.contentType),
    name: row.name,
    url: Uri.parse(row.url),
    tvgId: row.tvgId,
    logo: row.logo == null ? null : Uri.parse(row.logo!),
    metadata: Map<String, String>.from(jsonDecode(row.metadataJson) as Map),
  );

  ChannelsCompanion _toCompanion(Channel channel) => ChannelsCompanion.insert(
    sourceId: channel.sourceId,
    refKey: channel.ref.key,
    categoryId: Value(channel.categoryId),
    contentType: channel.type.name,
    name: channel.name,
    url: channel.url.toString(),
    tvgId: Value(channel.tvgId),
    logo: Value(channel.logo?.toString()),
    metadataJson: Value(jsonEncode(channel.metadata)),
  );

  Category _categoryToEntity(CategoryRow row) => Category(
    id: row.id,
    sourceId: row.sourceId,
    type: ContentType.values.byName(row.contentType),
    name: row.name,
    order: row.sortOrder,
  );
}
