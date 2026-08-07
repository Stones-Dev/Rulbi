import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iptv_core/iptv_core.dart';

import '../sources/source_providers.dart';
import 'epg_ingest.dart';
import 'xtream_epg_fallback.dart';

/// Fallback bajo demanda de EPG Xtream por canal (S5.5, Bloque A3) — se
/// construye su propio `XtreamClient`/transporte por invocación (mismo
/// criterio que `xtreamProbeProvider`/`xtreamImportChannelSourceProvider`:
/// nunca compartido entre llamadas).
final xtreamEpgFallbackProvider = Provider<XtreamEpgFallback>((ref) {
  return XtreamEpgFallback(
    epgRepository: ref.watch(epgRepositoryProvider),
    writer: ref.watch(xmltvEpgWriterProvider),
    sources: ref.watch(sourceRepositoryProvider),
    secureStore: ref.watch(secureCredentialStoreProvider),
  );
});

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
  EpgNowController({required this.repository, this.ensureEpgFor});

  final EpgRepository repository;

  /// Fallback bajo demanda de EPG Xtream (S5.5, Bloque A3) — `null` en la
  /// mayoría de tests y en cualquier composición que no lo necesite
  /// (comportamiento 100% igual al de antes de esta ola). Cuando se
  /// provee, [_flush] lo invoca una única vez por `tvgId` que resultó sin
  /// "ahora/siguiente", solo si [request] vino acompañado del [Channel]
  /// (ver su docstring) — nunca en bloque, nunca más de una vez por
  /// `tvgId` mientras este controller viva.
  final Future<bool> Function(Channel channel, DateTime at)? ensureEpgFor;

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

  /// Canal asociado a un `tvgId` pendiente, solo si [request] lo trajo —
  /// es lo único que [ensureEpgFor] necesita (`sourceId`,
  /// `x-xtream-stream-id`) y que este controller no tiene por su cuenta
  /// (solo trabaja con `tvgId`s sueltos, ver docstring de la clase).
  final Map<String, Channel> _pendingChannels = {};
  bool _flushScheduled = false;

  EpgProgramme? nowAiring(String? tvgId) =>
      tvgId == null ? null : _index?.nowAiring(tvgId);

  EpgProgramme? nextUp(String? tvgId) =>
      tvgId == null ? null : _index?.nextUp(tvgId);

  /// Encola [tvgId] para el próximo lote, si no está ya resuelto. No-op si
  /// [tvgId] es `null` (canal sin `tvgId`, ver docstring de `Channel`) —
  /// ese canal nunca tendrá EPG, no hay nada que pedir.
  ///
  /// [channel] es opcional y solo alimenta [ensureEpgFor] (S5.5, Bloque
  /// A3): sin él, un `tvgId` sin "ahora/siguiente" se queda así hasta que
  /// alguna llamada posterior sí lo traiga — el resto del comportamiento
  /// (caché por `_known`, batching) es idéntico con o sin `channel`.
  void request(String? tvgId, DateTime at, {Channel? channel}) {
    if (tvgId == null || _known.contains(tvgId)) return;
    if (channel != null) _pendingChannels[tvgId] = channel;
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
    final channelsForIds = <String, Channel>{
      for (final id in ids) id: ?_pendingChannels.remove(id),
    };

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

    final fallback = ensureEpgFor;
    if (fallback == null) return;
    for (final id in ids) {
      if (loaded.entries.containsKey(id)) continue;
      final channel = channelsForIds[id];
      if (channel == null) continue;
      unawaited(_tryFallback(fallback, channel, at));
    }
  }

  /// Best-effort: un fallo del fallback (red, panel sin credencial, etc.)
  /// nunca debe romper esta pantalla — mismo criterio P7 que el resto de
  /// EPG. Si escribió programas nuevos, libera el `tvgId` de [_known] y lo
  /// vuelve a encolar — sin esto, el `tvgId` seguiría marcado como
  /// "ya resuelto (sin guía)" para siempre, aunque el fallback acabara de
  /// escribir datos reales.
  Future<void> _tryFallback(
    Future<bool> Function(Channel channel, DateTime at) fallback,
    Channel channel,
    DateTime at,
  ) async {
    try {
      final wrote = await fallback(channel, at);
      if (!wrote || _disposed) return;
      final tvgId = channel.tvgId;
      if (tvgId == null) return;
      _known.remove(tvgId);
      request(tvgId, at, channel: channel);
    } catch (_) {
      // Silencioso a propósito — ver docstring de [ensureEpgFor].
    }
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
/// de vida de widget), cableado con el fallback Xtream real (S5.5, Bloque
/// A3). Solo para pantallas reales — un test con `ProviderContainer` (que
/// no es un `WidgetRef`) construye
/// `EpgNowController(repository: container.read(epgRepositoryProvider))`
/// directamente, sin pasar por este helper (y sin `ensureEpgFor`, salvo
/// que el propio test lo necesite).
EpgNowController createEpgNowController(WidgetRef ref) => EpgNowController(
  repository: ref.read(epgRepositoryProvider),
  ensureEpgFor: (channel, at) =>
      ref.read(xtreamEpgFallbackProvider).ensureEpgFor(channel, now: at),
);

/// Ingesta de guía por fuente (S5.5, Bloque B4) — compone `epgSourceProvider`
/// (descarga) + `xmltvEpgWriterProvider` (escritura), el puerto que
/// `RunEpgRefresh` (`core`) necesita sin depender de ninguno de los dos
/// directamente (P6).
final epgIngestProvider = Provider<EpgIngestPort>((ref) {
  return AppEpgIngestPort(
    epgSource: ref.watch(epgSourceProvider),
    writer: ref.watch(xmltvEpgWriterProvider),
  );
});

/// Intervalo por defecto (S5.5): 6 h, ver docstring de `EpgRefreshPolicy`
/// en `core`. Provider propio (en vez de `const EpgRefreshPolicy()` inline
/// en `runEpgRefreshProvider`) para que la futura pantalla de Ajustes
/// (ui-spec §2.15) tenga un único sitio que overridear cuando exista.
final epgRefreshPolicyProvider = Provider<EpgRefreshPolicy>((ref) => const EpgRefreshPolicy());

final runEpgRefreshProvider = Provider<RunEpgRefresh>((ref) {
  return DefaultRunEpgRefresh(
    ref.watch(sourceRepositoryProvider),
    ref.watch(epgIngestProvider),
    ref.watch(clockProvider),
    policy: ref.watch(epgRefreshPolicyProvider),
  );
});

/// Wiring de producción del refresco automático de guía (S5.5) —
/// `Stream.periodic(policy.minInterval)` como único trigger: sin
/// infraestructura de background nueva (eso es F6), sujeto de todas
/// formas a `EpgRefreshPolicy.minInterval` vía `RunEpgRefresh.runIfDue`
/// (mismo patrón que `PurgeScheduler`, ver `maintenance_providers.dart`).
/// Arrancado una vez desde `IptvApp.initState` (`main.dart`).
final epgRefreshSchedulerProvider = Provider<PeriodicJobScheduler>((ref) {
  final policy = ref.watch(epgRefreshPolicyProvider);
  final scheduler = PeriodicJobScheduler(
    ref.watch(runEpgRefreshProvider),
    Stream<void>.periodic(policy.minInterval),
  );
  ref.onDispose(() => unawaited(scheduler.stop()));
  return scheduler;
});
