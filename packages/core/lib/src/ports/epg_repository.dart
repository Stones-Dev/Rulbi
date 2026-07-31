import '../entities/epg_programme.dart';

abstract interface class EpgRepository {
  /// Solo la ventana temporal visible viene de SQLite (ui-spec §2.4): la
  /// implementación real nunca carga un XMLTV completo en memoria (P1,
  /// RNF-03).
  Future<List<EpgProgramme>> programmesFor(
    String tvgId, {
    required DateTime from,
    required DateTime to,
  });

  EpgProgramme? nowAiring(String tvgId, DateTime at);

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
