import 'package:drift/drift.dart';
import 'package:iptv_core/iptv_core.dart';

import '../db/database.dart';

/// Solo la ventana temporal visible viene de SQLite (ui-spec §2.4, P1):
/// nunca se carga un XMLTV completo en memoria. La escritura masiva
/// (T1.3, parser) llega bloqueada en T1.1; aquí solo el esquema y las
/// consultas.
final class DriftEpgRepository implements EpgRepository {
  DriftEpgRepository(this._db);

  final IptvDatabase _db;

  /// Tamaño de lote de la purga por ventana — mismo valor que
  /// `DriftChannelRepository._batchSize` (T1.6b), sin que haya que
  /// coordinarlo entre repositorios.
  static const int _batchSize = 500;

  @override
  Future<List<EpgProgramme>> programmesFor(
    String tvgId, {
    required DateTime from,
    required DateTime to,
  }) async {
    final rows =
        await (_db.select(_db.epgProgrammes)..where(
              (p) =>
                  p.tvgId.equals(tvgId) &
                  p.start.isSmallerThanValue(to) &
                  p.stop.isBiggerThanValue(from),
            ))
            .get();
    return rows.map(_toEntity).toList();
  }

  /// SQLite tiene un límite de ~999 parámetros de sentencia; se trocea en
  /// bloques del mismo tamaño que el resto de lotes del repositorio para
  /// no coordinar un segundo valor.
  static const int _inClauseChunkSize = 500;

  /// Carga "ahora/siguiente" para [tvgIds] en un único snapshot (S5 · Ola
  /// 2, ver docstring del puerto). Una sola consulta por bloque de
  /// `tvgIds` sobre `idx_epg_tvg_id_start` (`stop > at` descarta lo que ya
  /// terminó de una vez): entre las filas restantes de un mismo `tvgId`,
  /// la que cubre `at` (`start <= at`) es "ahora" y la de `start` mínimo
  /// por encima de `at` es "siguiente" — se resuelven las dos en la misma
  /// pasada en memoria en vez de con dos consultas SQL por canal.
  @override
  Future<EpgNowIndex> nowAndNextFor(Set<String> tvgIds, DateTime at) async {
    if (tvgIds.isEmpty) return EpgNowIndex(at: at, entries: const {});

    final entries = <String, EpgNowNext>{};
    for (final chunk in _chunked(tvgIds.toList(), _inClauseChunkSize)) {
      final rows =
          await (_db.select(_db.epgProgrammes)
                ..where(
                  (p) => p.tvgId.isIn(chunk) & p.stop.isBiggerThanValue(at),
                )
                ..orderBy([(p) => OrderingTerm.asc(p.start)]))
              .get();

      final byTvgId = <String, List<EpgProgrammeRow>>{};
      for (final row in rows) {
        (byTvgId[row.tvgId] ??= []).add(row);
      }

      for (final entry in byTvgId.entries) {
        EpgProgrammeRow? nowRow;
        EpgProgrammeRow? nextRow;
        for (final row in entry.value) {
          if (!row.start.isAfter(at)) {
            nowRow = row; // start <= at < stop, ya filtrado por el WHERE
          } else {
            nextRow ??= row; // orderBy asc: el primero que llega es el mínimo
          }
        }
        entries[entry.key] = EpgNowNext(
          now: nowRow == null ? null : _toEntity(nowRow),
          next: nextRow == null ? null : _toEntity(nextRow),
        );
      }
    }
    return EpgNowIndex(at: at, entries: entries);
  }

  /// Purga por ventana ("Ventana y purga EPG", S2): complemento exacto de
  /// `XmltvWindow.overlaps` (`packages/protocols`) — se borra un programa
  /// `[start, stop)` si `stop <= from` o `start >= to`. Un `DELETE` sobre
  /// cientos de miles de programas no puede mantener el lock de escritura
  /// de SQLite mientras un import está corriendo (mismo riesgo que
  /// `_flushTombstones` de `DriftChannelRepository`, T1.6b), así que se
  /// hace en lotes acotados con una transacción por lote y cesión real
  /// entre lotes — reanudable e idempotente: progreso parcial es un
  /// estado válido, y una segunda corrida sobre lo ya purgado no borra
  /// nada más.
  @override
  Future<int> purgeOutsideWindow({
    required DateTime from,
    required DateTime to,
  }) async {
    var totalDeleted = 0;
    while (true) {
      final batch = await (_db.selectOnly(_db.epgProgrammes)
            ..addColumns([_db.epgProgrammes.tvgId, _db.epgProgrammes.start])
            ..where(
              _db.epgProgrammes.stop.isSmallerOrEqualValue(from) |
                  _db.epgProgrammes.start.isBiggerOrEqualValue(to),
            )
            ..limit(_batchSize))
          .get();
      if (batch.isEmpty) break;

      await _db.transaction(() async {
        await _db.batch((b) {
          for (final row in batch) {
            b.delete(
              _db.epgProgrammes,
              EpgProgrammesCompanion(
                tvgId: Value(row.read(_db.epgProgrammes.tvgId)!),
                start: Value(row.read(_db.epgProgrammes.start)!),
              ),
            );
          }
        });
      });
      totalDeleted += batch.length;

      // Cesión real (macrotask) entre lotes, no solo microtask — mismo
      // patrón que `DriftChannelRepository.importSourceContent` (T1.6b):
      // sin esto, un `while` que solo hace `await` sobre operaciones de
      // BD ya resueltas en microtasks puede encadenar cientos de lotes
      // seguidos sin que el event loop atienda nada más.
      await Future<void>.delayed(Duration.zero);
    }
    return totalDeleted;
  }

  EpgProgramme _toEntity(EpgProgrammeRow row) => EpgProgramme(
    tvgId: row.tvgId,
    start: row.start,
    stop: row.stop,
    title: row.title,
    description: row.description,
  );
}

Iterable<List<T>> _chunked<T>(List<T> items, int size) sync* {
  for (var i = 0; i < items.length; i += size) {
    yield items.sublist(i, i + size > items.length ? items.length : i + size);
  }
}
