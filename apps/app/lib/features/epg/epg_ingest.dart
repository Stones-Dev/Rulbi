import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_data/iptv_data.dart';

import '../sources/epg_source.dart';

/// Implementación de `EpgIngestPort` (S5.5, Bloque B4) — compone
/// [EpgSource] (descarga + parseo) y [XmltvEpgWriter] (escritura en
/// drift), el mismo par que ya usa
/// `ImportController._runEpgPhase` para el import manual. `core` no puede
/// depender de ninguno de los dos sin romper P6 (ni HTTP ni drift); esto
/// vive en `apps/app`, que sí conoce ambos.
final class AppEpgIngestPort implements EpgIngestPort {
  AppEpgIngestPort({required this.epgSource, required this.writer});

  final EpgSource epgSource;
  final XmltvEpgWriter writer;

  @override
  Future<EpgImportStats?> ingestFor(Source source, {required DateTime now}) async {
    final outcome = epgSource.epgFor(source, now: now);
    if (outcome == null) return null;

    // Mismo motivo que `ImportController._runEpgPhase`: si `write()` falla
    // porque `entries` mismo falló, `outcome.report` completa con el
    // mismo error y nunca se llega a `await`lo — sin `.ignore()`, Dart lo
    // reporta como excepción sin manejar aunque `DefaultRunEpgRefresh` ya
    // la esté tratando (try/catch por fuente).
    outcome.report.ignore();

    return writer.write(outcome.entries, now: now);
  }
}
