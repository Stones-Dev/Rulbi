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

  /// Purga automática de programas fuera de la ventana útil (T1.3).
  Future<void> purgeBefore(DateTime cutoff);
}
