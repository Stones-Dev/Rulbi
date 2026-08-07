import 'epg_programme.dart';

/// Programa "ahora" y "siguiente" de un canal, en el instante con que se
/// cargó el [EpgNowIndex] que lo contiene.
final class EpgNowNext {
  const EpgNowNext({this.now, this.next});

  /// El programa que cubre `[start, stop)` el instante consultado, o
  /// `null` si no hay ninguno (hueco en la guía) — ver [EpgNowIndex.at].
  final EpgProgramme? now;

  /// El primer programa que empieza después del instante consultado, o
  /// `null` si la guía no llega tan lejos.
  final EpgProgramme? next;
}

/// Snapshot inmutable de "ahora/siguiente" para un lote de `tvgId`,
/// cargado por `EpgRepository.nowAndNextFor` (S5 · Ola 2, ui-spec §2.2 y
/// §2.3). Separa la carga (async, por lotes de canales visibles) de la
/// lectura (síncrona, en `build()`): necesario porque un listado
/// virtualizado de 100k canales no puede permitirse una consulta SQL por
/// fila, y porque el puerto original (`nowAiring` síncrono) no puede
/// consultar SQLite sin haber cargado antes un snapshot.
final class EpgNowIndex {
  const EpgNowIndex({required this.at, required this.entries});

  /// El instante para el que se calculó este índice — el mismo que se pasó
  /// a `nowAndNextFor`. No tiene por qué ser `DateTime.now()`: los tests
  /// (y el reloj inyectado de la UI) fijan un instante determinista.
  final DateTime at;

  /// Por `tvgId`. Público (mismo criterio que el resto de entidades de
  /// `core`, p. ej. `Favorite`/`Channel`: datos, no una clase con estado
  /// que proteger) — `nowAiring`/`nextUp` son la forma cómoda de leerlo,
  /// no la única.
  final Map<String, EpgNowNext> entries;

  /// `null` si [tvgId] no tiene guía, o si la tiene pero ningún programa
  /// cubre [at] (hueco en la guía) — ambos casos son el mismo estado para
  /// la UI: "sin EPG ahora" (ui-spec §2.3, "ítem sin subtítulo"), nunca un
  /// dato inventado.
  EpgProgramme? nowAiring(String tvgId) => entries[tvgId]?.now;

  EpgProgramme? nextUp(String tvgId) => entries[tvgId]?.next;

  /// `true` si algún programa "ahora" cargado en este índice ya terminó a
  /// [instant] — señal de que el índice quedó obsoleto y toca recargarlo
  /// contra la BD, en vez de confiar en el snapshot indefinidamente. Un
  /// tick del reloj que no cruza ningún `stop` no invalida nada: la barra
  /// de progreso puede seguir leyendo este mismo snapshot sin tocar SQLite.
  bool isStaleAt(DateTime instant) => entries.values.any(
    (entry) => entry.now != null && !entry.now!.stop.isAfter(instant),
  );
}
