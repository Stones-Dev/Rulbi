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

  @override
  EpgProgramme? nowAiring(String tvgId, DateTime at) {
    // Nota: intencionalmente síncrono en el puerto (ui-spec §2.2, lectura
    // desde una caché ya cargada); la implementación real de esta
    // consulta puntual llega con T1.3, cuando exista un flujo real de
    // datos EPG que poblar y contra el que medir el caso de uso.
    throw UnimplementedError(
      'nowAiring: pendiente de T1.3 (parser XMLTV que puebla epg_programmes)',
    );
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
