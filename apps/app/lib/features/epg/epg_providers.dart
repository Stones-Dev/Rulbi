import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iptv_core/iptv_core.dart';

import '../sources/source_providers.dart';

/// Reloj compartido de la barra de progreso EPG (S5 · Ola 2, D7 del plan
/// de la ola): un único `ValueListenable<DateTime>` a nivel de app que
/// emite cada 30 s. Un programa real dura entre 30 y 90 minutos — con esa
/// granularidad la barra avanza menos de un píxel entre ticks, así que no
/// hace falta nada más fino, y cada `_EpgProgressBar` que escucha este
/// mismo objeto se repinta sin reconstruir el resto del árbol (ver
/// `epg_progress_bar.dart`).
final epgClockProvider = Provider<ValueListenable<DateTime>>((ref) {
  final notifier = ValueNotifier<DateTime>(DateTime.now());
  final timer = Timer.periodic(
    const Duration(seconds: 30),
    (_) => notifier.value = DateTime.now(),
  );
  ref.onDispose(() {
    timer.cancel();
    notifier.dispose();
  });
  return notifier;
});

/// Carga "ahora/siguiente" por lotes según lo que las filas van pidiendo
/// (S5 · Ola 2, ADR-008) — mismo espíritu que `ChannelPageCache`
/// (construido a mano por cada pantalla, no un provider global, porque
/// cada pantalla tiene su propio conjunto de canales visibles) pero sin
/// paginación propia: aquí el "lote" lo define quién construye en el mismo
/// frame, no un tamaño de página fijo.
///
/// [ChannelRow]/las tarjetas de Home llaman [request] en cada `build()`;
/// varias filas construidas en el mismo frame (el caso normal al hacer
/// scroll) se resuelven en una sola consulta a `EpgRepository
/// .nowAndNextFor`, agendada en un microtask — nunca una consulta por
/// fila. La lectura (`nowAiring`/`nextUp`) es siempre síncrona.
class EpgNowController extends ChangeNotifier {
  EpgNowController({required this.repository});

  final EpgRepository repository;

  EpgNowIndex? _index;

  /// `tvgId`s ya resueltos contra la BD, tengan o no guía. Distinto de
  /// `_index.entries.keys` a propósito: un canal sin guía nunca aparece en
  /// `entries` (`EpgNowIndex` solo guarda pares con datos), así que sin
  /// este set separado [request] no tendría forma de saber "ya pregunté
  /// por este canal y la respuesta fue 'nada'" — reintentaría en cada
  /// `build()`, y cada intento dispararía `notifyListeners()`, que
  /// reconstruye el widget que vuelve a llamar `request()`: un bucle de
  /// reconstrucción infinito para cualquier canal sin EPG.
  final Set<String> _known = {};
  final Set<String> _pending = {};
  bool _flushScheduled = false;

  EpgProgramme? nowAiring(String? tvgId) =>
      tvgId == null ? null : _index?.nowAiring(tvgId);

  EpgProgramme? nextUp(String? tvgId) =>
      tvgId == null ? null : _index?.nextUp(tvgId);

  /// Encola [tvgId] para el próximo lote, si no está ya resuelto. No-op si
  /// [tvgId] es `null` (canal sin `tvgId`, ver docstring de `Channel`) —
  /// ese canal nunca tendrá EPG, no hay nada que pedir.
  void request(String? tvgId, DateTime at) {
    if (tvgId == null || _known.contains(tvgId)) return;
    if (_pending.add(tvgId) && !_flushScheduled) {
      _flushScheduled = true;
      scheduleMicrotask(() => _flush(at));
    }
  }

  Future<void> _flush(DateTime at) async {
    _flushScheduled = false;
    if (_pending.isEmpty) return;
    final ids = Set<String>.of(_pending);
    _pending.clear();

    final loaded = await repository.nowAndNextFor(ids, at);
    if (_disposed) return;
    _known.addAll(ids);
    // Se combina con lo ya cargado (canales de un lote anterior siguen
    // pudiendo estar en pantalla) en vez de descartarlo — este índice no
    // implementa un LRU como `ChannelPageCache` a propósito: cada entrada
    // es unas pocas decenas de bytes (dos `EpgProgramme` cortos), varios
    // órdenes de magnitud por debajo de lo que justificaría el mismo
    // tratamiento que la caché de páginas (RNF-04 aplica de verdad a
    // `Channel`/imágenes, no aquí).
    _index = EpgNowIndex(
      at: at,
      entries: {...?_index?.entries, ...loaded.entries},
    );
    notifyListeners();
  }

  /// Se llama en cada tick de [epgClockProvider] (una vez por pantalla que
  /// use este controller, no una vez por fila): si algún "ahora" cargado
  /// ya terminó, lo descarta (junto con su entrada en [_known]) y deja que
  /// la próxima [request] de esa fila lo repueble — un tick normal, sin
  /// nada que haya terminado, no toca la BD (`EpgNowIndex.isStaleAt`). Solo
  /// se invalidan los canales realmente obsoletos, no el índice entero:
  /// los demás siguen sirviendo desde el mismo snapshot.
  void invalidateIfStale(DateTime at) {
    final index = _index;
    if (index == null || !index.isStaleAt(at)) return;

    final staleTvgIds = [
      for (final entry in index.entries.entries)
        if (entry.value.now != null && !entry.value.now!.stop.isAfter(at))
          entry.key,
    ];
    final remainingEntries = Map<String, EpgNowNext>.of(index.entries)
      ..removeWhere((tvgId, _) => staleTvgIds.contains(tvgId));
    _index = EpgNowIndex(at: at, entries: remainingEntries);
    _known.removeAll(staleTvgIds);

    for (final tvgId in staleTvgIds) {
      request(tvgId, at);
    }
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Construye un [EpgNowController] nuevo por cada pantalla que lo necesita
/// (mismo criterio que `ChannelPageCache`: no es un estado global — cada
/// pantalla tiene su propio conjunto de canales visibles y su propio ciclo
/// de vida de widget). Solo para pantallas reales — un test con
/// `ProviderContainer` (que no es un `WidgetRef`) construye
/// `EpgNowController(repository: container.read(epgRepositoryProvider))`
/// directamente, sin pasar por este helper.
EpgNowController createEpgNowController(WidgetRef ref) =>
    EpgNowController(repository: ref.read(epgRepositoryProvider));
