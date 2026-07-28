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

  @override
  Future<void> purgeBefore(DateTime cutoff) {
    return (_db.delete(
      _db.epgProgrammes,
    )..where((p) => p.stop.isSmallerThanValue(cutoff))).go();
  }

  EpgProgramme _toEntity(EpgProgrammeRow row) => EpgProgramme(
    tvgId: row.tvgId,
    start: row.start,
    stop: row.stop,
    title: row.title,
    description: row.description,
  );
}
