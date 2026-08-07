import '../entities/source.dart';
import 'epg_repository.dart';

/// Ingesta la guía de una fuente concreta — puerto de `core` para
/// `RunEpgRefresh` (S5.5, Bloque B1). Análogo a `EpgSource`
/// (`apps/app/lib/features/sources/epg_source.dart`) compuesto con
/// `XmltvEpgWriter` (`packages/data`), pero visto desde `core`:
/// `RunEpgRefresh` no puede depender de ninguno de los dos sin romper P6
/// (el dominio no conoce ni la plataforma HTTP ni drift) — `apps/app`
/// implementa este puerto uniendo ambos, con el mismo patrón que ya usa
/// `ImportController._runEpgPhase` para el import manual.
abstract interface class EpgIngestPort {
  /// `null` si [source] no tiene guía configurada — mismo criterio que
  /// `EpgSource.epgFor`, pero ya resuelto hasta "programas escritos" (un
  /// M3U sin `epgUrl`). Una fuente Xtream nunca devuelve `null` (su guía
  /// es `xmltv.php`, ver S5.5 Bloque A).
  Future<EpgImportStats?> ingestFor(Source source, {required DateTime now});
}
