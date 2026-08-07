import '../entities/epg_now_index.dart';
import '../entities/epg_programme.dart';

abstract interface class EpgRepository {
  /// Solo la ventana temporal visible viene de SQLite (ui-spec §2.4, P1):
  /// nunca se carga un XMLTV completo en memoria. La escritura masiva
  /// (T1.3, parser) llega bloqueada en T1.1; aquí solo el esquema y las
  /// consultas.
  Future<List<EpgProgramme>> programmesFor(
    String tvgId, {
    required DateTime from,
    required DateTime to,
  });

  /// Carga "ahora/siguiente" para un lote de canales visibles (S5 · Ola 2,
  /// ui-spec §2.2/§2.3), como un único snapshot (`EpgNowIndex`) para leer
  /// de forma síncrona mientras se pinta el listado. Sustituye a un
  /// `nowAiring(String, DateTime)` síncrono anterior que no podía
  /// implementarse contra SQLite (no hay consulta síncrona posible) y que,
  /// aunque hubiera podido, habría significado una consulta por fila en un
  /// listado virtualizado de 100k canales — inviable (RNF-01).
  ///
  /// [tvgIds] sin guía simplemente no aparecen en el índice devuelto (ver
  /// `EpgNowIndex.nowAiring`, que ya trata "ausente" y "sin programa en
  /// [at]" como el mismo estado).
  Future<EpgNowIndex> nowAndNextFor(Set<String> tvgIds, DateTime at);

  /// Purga automática de programas fuera de la ventana útil ("Ventana y
  /// purga EPG", S2). Criterio complementario exacto de `XmltvWindow
  /// .overlaps` (`packages/protocols`, bordes excluyentes por ambos
  /// lados): se borra un programa `[start, stop)` si `stop <= from` o
  /// `start >= to`. Devuelve el número de filas borradas — lo que agrega
  /// `PurgeStats` y lo que verifica la idempotencia (segunda corrida ⇒ 0).
  ///
  /// Sustituye a un `purgeBefore(cutoff)` anterior (solo cubría el lado
  /// pasado, `stop < cutoff`, sin el `+7d`) que nunca llegó a tener
  /// llamador ni test.
  Future<int> purgeOutsideWindow({required DateTime from, required DateTime to});
}

/// Recuento de lo que hizo un escritor XMLTV→drift (ADR-008, S5 · Ola 2) —
/// análogo a `SourceImportStats` (`ports/channel_repository.dart`, T1.9),
/// aplicado a las dos tablas que puebla el escritor en el mismo pase
/// (`epg_programmes`, `epg_channels`) en vez de a una sola.
///
/// A diferencia de `SourceImportStats`, no hay `tombstoned`/`resurrected`:
/// el EPG no implementa `Syncable` (no tiene `deletedAt`, ver
/// `EpgProgramme`), se purga por ventana temporal con `DELETE` real
/// (`purgeOutsideWindow`), no con tombstones — un contador de tombstones
/// de EPG no significaría nada.
final class EpgImportStats {
  const EpgImportStats({
    required this.programmesInserted,
    required this.programmesUpdated,
    required this.programmesUnchanged,
    required this.channelsInserted,
    required this.channelsUpdated,
    required this.channelsUnchanged,
    required this.duplicateKeys,
  });

  final int programmesInserted;
  final int programmesUpdated;
  final int programmesUnchanged;

  final int channelsInserted;
  final int channelsUpdated;
  final int channelsUnchanged;

  /// Entradas con la misma clave (`(tvgId, start)` para programas, `tvgId`
  /// para canales de guía) repetidas dentro del *mismo* XMLTV (ADR-008
  /// §Decisión 3) — gana la última leída en el stream, se cuenta para que
  /// el informe de import lo muestre. Mismo espíritu que `duplicateRefs`
  /// de `SourceImportStats`, distinta clave.
  final int duplicateKeys;

  Map<String, Object?> toJson() => {
    'programmesInserted': programmesInserted,
    'programmesUpdated': programmesUpdated,
    'programmesUnchanged': programmesUnchanged,
    'channelsInserted': channelsInserted,
    'channelsUpdated': channelsUpdated,
    'channelsUnchanged': channelsUnchanged,
    'duplicateKeys': duplicateKeys,
  };

  factory EpgImportStats.fromJson(Map<String, Object?> json) => EpgImportStats(
    programmesInserted: json['programmesInserted'] as int,
    programmesUpdated: json['programmesUpdated'] as int,
    programmesUnchanged: json['programmesUnchanged'] as int,
    channelsInserted: json['channelsInserted'] as int,
    channelsUpdated: json['channelsUpdated'] as int,
    channelsUnchanged: json['channelsUnchanged'] as int,
    duplicateKeys: json['duplicateKeys'] as int,
  );

  @override
  bool operator ==(Object other) =>
      other is EpgImportStats &&
      other.programmesInserted == programmesInserted &&
      other.programmesUpdated == programmesUpdated &&
      other.programmesUnchanged == programmesUnchanged &&
      other.channelsInserted == channelsInserted &&
      other.channelsUpdated == channelsUpdated &&
      other.channelsUnchanged == channelsUnchanged &&
      other.duplicateKeys == duplicateKeys;

  @override
  int get hashCode => Object.hash(
    programmesInserted,
    programmesUpdated,
    programmesUnchanged,
    channelsInserted,
    channelsUpdated,
    channelsUnchanged,
    duplicateKeys,
  );

  @override
  String toString() =>
      'EpgImportStats(programmes: +$programmesInserted ~$programmesUpdated '
      '=$programmesUnchanged, channels: +$channelsInserted ~$channelsUpdated '
      '=$channelsUnchanged, duplicateKeys: $duplicateKeys)';
}
