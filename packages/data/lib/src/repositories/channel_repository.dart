import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:iptv_core/iptv_core.dart';

import '../db/content_hash.dart';
import '../db/database.dart';

/// Implementa `ChannelRepository` y `ChannelSearchPort` (T1.6) sobre el
/// esquema de `channels`/`categories`/el índice FTS5 (T1.5).
final class DriftChannelRepository
    implements ChannelRepository, ChannelSearchPort {
  DriftChannelRepository(this._db);

  final IptvDatabase _db;

  /// Tamaño de lote para los `INSERT`/`UPDATE` del diff (T1.6b) — el mismo
  /// valor por defecto que usan los parsers de `protocols` para sus
  /// lotes de canales, sin que haya que coordinarlo entre capas.
  static const int _batchSize = 500;

  /// Cada cuántos canales del stream de entrada se cede el control real
  /// (macrotask) durante la deduplicación (T1.6b) — más fino que
  /// `_batchSize` a propósito: aquí no hay ningún `_flush*` que ya esté
  /// cediendo el control por su cuenta, así que es el único punto de
  /// respiro del event loop durante toda esa fase.
  static const int _yieldEvery = 100;

  @override
  Future<SourceImportStats> importSourceContent(
    String sourceId,
    Stream<Channel> channels, {
    required DateTime now,
  }) {
    return _db.transaction(() async {
      final existing = await _existingSnapshot(sourceId);

      // Se deduplica por `ChannelRef` ANTES de decidir insert/update/
      // tombstone: dos entradas del mismo import con el mismo `refKey`
      // (frecuente en M3U sin `tvg-id`, ver hallazgo de T1.5b) no se
      // pueden clasificar una a una según llegan — la primera "sería" un
      // insert hasta que la segunda demuestra que había que esperarla.
      // Gana la última (last-writer-wins), y cada sustitución cuenta en
      // `duplicateRefs`. Esto obliga a materializar el import
      // deduplicado en memoria antes de escribir nada (no solo el
      // snapshot de lo existente) — el precio de soportar duplicados
      // intra-fuente con honestidad en vez de reventar el `UNIQUE
      // (sourceId, refKey)` a mitad de import; documentado como riesgo
      // de memoria en el plan de T1.6b.
      final deduped = <String, _Incoming>{};
      var duplicateRefs = 0;
      var drained = 0;
      await for (final channel in channels) {
        final refKey = channel.ref.key;
        if (deduped.containsKey(refKey)) duplicateRefs++;
        deduped[refKey] = _Incoming(channel, _hashOf(channel));

        // Cede el control real (macrotask, no solo microtask) cada
        // `_batchSize` canales: el productor (parser en isolate) entrega
        // sus lotes ya montados, así que sin esto un `await for` sobre
        // 100k canales puede procesar cientos seguidos sin que el event
        // loop llegue a atender nada más — el mismo tipo de bloque largo
        // que RNF-01 mide como jank (a diferencia de la clasificación de
        // más abajo, aquí no hay ningún `_flush*` que ya esté cediendo
        // el control por su cuenta).
        drained++;
        if (drained % _yieldEvery == 0) {
          await Future<void>.delayed(Duration.zero);
        }
      }

      var inserted = 0;
      var updated = 0;
      var unchanged = 0;
      var resurrected = 0;
      // Clasifica y descarga en lotes de `_batchSize` DURANTE la misma
      // pasada, no "clasifica los 100k y luego descarga": un `for`
      // síncrono sobre 100k entradas sin ceder el control de vuelta al
      // event loop es justo el tipo de bloque largo que RNF-01 mide como
      // jank (medido: subía a ~200 ms de gap máximo frente a los 18 ms de
      // T1.5b). Cada `_flush*` es `await`, así que interlava esta
      // clasificación con el resto del isolate cada `_batchSize`
      // elementos en vez de en un único tramo síncrono.
      var pendingInserts = <ChannelsCompanion>[];
      var pendingUpdates = <(int, ChannelsCompanion)>[];

      for (final entry in deduped.entries) {
        final existingRow = existing[entry.key];
        final companion = _toCompanion(
          entry.value.channel,
        ).copyWith(contentHash: Value(entry.value.hash));

        if (existingRow == null) {
          pendingInserts.add(companion);
          inserted++;
        } else if (existingRow.deletedAt != null) {
          pendingUpdates.add((
            existingRow.id,
            companion.copyWith(deletedAt: const Value(null)),
          ));
          resurrected++;
        } else if (existingRow.contentHash != entry.value.hash) {
          pendingUpdates.add((existingRow.id, companion));
          updated++;
        } else {
          unchanged++;
        }

        if (pendingInserts.length >= _batchSize) {
          await _flushInserts(pendingInserts);
          pendingInserts = [];
        }
        if (pendingUpdates.length >= _batchSize) {
          await _flushUpdates(pendingUpdates);
          pendingUpdates = [];
        }
      }

      await _flushInserts(pendingInserts);
      await _flushUpdates(pendingUpdates);

      // Tombstone: lo que quedó en `existing`, no visto en este import, y
      // todavía vivo — un tombstone ya existente no se vuelve a tocar
      // (es lo que hace idempotente un refresco sin cambios: cero writes
      // de más, ver test de idempotencia).
      final toTombstone = [
        for (final e in existing.entries)
          if (!deduped.containsKey(e.key) && e.value.deletedAt == null)
            e.value.id,
      ];
      await _flushTombstones(toTombstone, now);

      return SourceImportStats(
        inserted: inserted,
        updated: updated,
        unchanged: unchanged,
        tombstoned: toTombstone.length,
        resurrected: resurrected,
        duplicateRefs: duplicateRefs,
      );
    });
  }

  /// Una sola consulta de 4 columnas estrechas — no arrastra `url`/
  /// `metadataJson` (el grueso de la tabla) de las filas existentes solo
  /// para poder compararlas, que es justo lo que el `content_hash` evita.
  Future<Map<String, _ExistingChannel>> _existingSnapshot(
    String sourceId,
  ) async {
    final query = _db.selectOnly(_db.channels)
      ..addColumns([
        _db.channels.refKey,
        _db.channels.id,
        _db.channels.contentHash,
        _db.channels.deletedAt,
      ])
      ..where(_db.channels.sourceId.equals(sourceId));

    final rows = await query.get();
    return {
      for (final row in rows)
        row.read(_db.channels.refKey)!: _ExistingChannel(
          id: row.read(_db.channels.id)!,
          contentHash: row.read(_db.channels.contentHash),
          deletedAt: row.read(_db.channels.deletedAt),
        ),
    };
  }

  Future<void> _flushInserts(List<ChannelsCompanion> rows) async {
    for (final chunk in _chunked(rows, _batchSize)) {
      await _db.batch((b) => b.insertAll(_db.channels, chunk));
    }
  }

  Future<void> _flushUpdates(List<(int, ChannelsCompanion)> updates) async {
    for (final chunk in _chunked(updates, _batchSize)) {
      await _db.batch((b) {
        for (final (id, companion) in chunk) {
          b.update(_db.channels, companion, where: (c) => c.id.equals(id));
        }
      });
    }
  }

  Future<void> _flushTombstones(List<int> ids, DateTime now) async {
    for (final chunk in _chunked(ids, _batchSize)) {
      await _db.batch((b) {
        for (final id in chunk) {
          b.update(
            _db.channels,
            ChannelsCompanion(deletedAt: Value(now)),
            where: (c) => c.id.equals(id),
          );
        }
      });
    }
  }

  /// Purga de tombstones huérfanos ("Tombstones huérfanos (purga)", S2):
  /// borra de verdad los canales tumbados (T1.6b, `deletedAt` no nulo)
  /// que ya no protegen ningún favorito ni watch-state vivo, más
  /// antiguos que [deletedBefore] (ventana de gracia configurable — un
  /// canal que reaparece antes lo resucita `importSourceContent`, no
  /// esta purga). "Vivo" = fila existente con `deletedAt IS NULL`; un
  /// favorito ya tumbado por el merge LWW no protege.
  ///
  /// Mismo patrón de lotes + transacción por lote + cesión real que
  /// `_flushTombstones` (arriba) y `DriftEpgRepository.purgeOutsideWindow`:
  /// un `DELETE` sobre cientos de miles de filas no puede mantener el
  /// lock de escritura mientras un import está corriendo. Idempotente y
  /// reanudable.
  ///
  /// No hay `FOREIGN KEY` entre `channels` y `favorites`/`watch_state`
  /// (se indexan por `(sourceId, refKey)`, no por `channels.id` — ADR-003),
  /// así que el borrado no cascadea nada; el trigger `channels_fts_ad`
  /// (`fts.drift`) mantiene el índice FTS5 sincronizado.
  @override
  Future<int> purgeOrphanTombstones({required DateTime deletedBefore}) async {
    var totalDeleted = 0;
    while (true) {
      final query = _db.selectOnly(_db.channels)
        ..addColumns([_db.channels.id])
        ..where(
          _db.channels.deletedAt.isNotNull() &
              _db.channels.deletedAt.isSmallerThanValue(deletedBefore) &
              notExistsQuery(
                _db.selectOnly(_db.favorites)
                  ..addColumns([_db.favorites.sourceId])
                  ..where(
                    _db.favorites.sourceId.equalsExp(_db.channels.sourceId) &
                        _db.favorites.refKey.equalsExp(_db.channels.refKey) &
                        _db.favorites.deletedAt.isNull(),
                  ),
              ) &
              notExistsQuery(
                _db.selectOnly(_db.watchState)
                  ..addColumns([_db.watchState.sourceId])
                  ..where(
                    _db.watchState.sourceId.equalsExp(_db.channels.sourceId) &
                        _db.watchState.refKey.equalsExp(_db.channels.refKey) &
                        _db.watchState.deletedAt.isNull(),
                  ),
              ),
        )
        ..limit(_batchSize);

      final ids = (await query.get())
          .map((row) => row.read(_db.channels.id)!)
          .toList();
      if (ids.isEmpty) break;

      await _db.transaction(() async {
        await _db.batch((b) {
          b.deleteWhere(_db.channels, (c) => c.id.isIn(ids));
        });
      });
      totalDeleted += ids.length;

      await Future<void>.delayed(Duration.zero);
    }
    return totalDeleted;
  }

  @override
  Future<List<Category>> categoriesFor(String sourceId) async {
    final rows = await (_db.select(
      _db.categories,
    )..where((c) => c.sourceId.equals(sourceId))).get();
    return rows.map(_categoryToEntity).toList();
  }

  /// Gestión de fuentes (ui-spec §2.10): nº de canales vivos por fuente.
  /// Agregado `COUNT(*)` sobre el motor — nunca trae las filas a Dart.
  @override
  Future<int> countBySource(String sourceId) async {
    final countExp = _db.channels.id.count();
    final query = _db.selectOnly(_db.channels)
      ..addColumns([countExp])
      ..where(
        _db.channels.sourceId.equals(sourceId) & _db.channels.deletedAt.isNull(),
      );
    final row = await query.getSingle();
    return row.read(countExp) ?? 0;
  }

  @override
  Stream<List<Channel>> watchChannels({required String categoryId}) {
    return (_db.select(_db.channels)..where(
          (c) => c.categoryId.equals(categoryId) & c.deletedAt.isNull(),
        ))
        .watch()
        .map((rows) => rows.map(_channelToEntity).toList());
  }

  /// RNF-01: percibido < 100 ms sobre 100k canales. `channels_fts` es
  /// una tabla "external content" (T1.5): la consulta hace `JOIN` con
  /// `channels` por `rowid`/`id` para recuperar la fila completa.
  ///
  /// `c.deleted_at IS NULL` (T1.6b): los triggers de `fts.drift` no
  /// distinguen un tombstone de un borrado real (son incondicionales),
  /// así que un canal tumbado sigue en el índice — se filtra aquí, no en
  /// el trigger (una external-content FTS5 cuyo trigger a veces no
  /// dispara se desincroniza del contenido real).
  @override
  Future<List<Channel>> search(String query, {int limit = 50}) async {
    final rows = await _db
        .customSelect(
          'SELECT c.* FROM channels_fts f '
          'JOIN channels c ON c.id = f.rowid '
          'WHERE channels_fts MATCH ? AND c.deleted_at IS NULL '
          'LIMIT ?',
          variables: [Variable<String>(query), Variable<int>(limit)],
          readsFrom: {_db.channels},
        )
        .get();

    return rows
        .map((row) => _channelToEntity(_db.channels.map(row.data)))
        .toList();
  }

  String _hashOf(Channel channel) => channelContentHash(
    ChannelFields(
      categoryId: channel.categoryId,
      contentType: channel.type.name,
      name: channel.name,
      url: channel.url.toString(),
      tvgId: channel.tvgId,
      logo: channel.logo?.toString(),
      metadataJson: jsonEncode(channel.metadata),
    ),
  );

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

Iterable<List<T>> _chunked<T>(List<T> items, int size) sync* {
  for (var i = 0; i < items.length; i += size) {
    yield items.sublist(i, i + size > items.length ? items.length : i + size);
  }
}

final class _ExistingChannel {
  const _ExistingChannel({
    required this.id,
    required this.contentHash,
    required this.deletedAt,
  });

  final int id;
  final String? contentHash;
  final DateTime? deletedAt;
}

final class _Incoming {
  const _Incoming(this.channel, this.hash);

  final Channel channel;
  final String hash;
}
