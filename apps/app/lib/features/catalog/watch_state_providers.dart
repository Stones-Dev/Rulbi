import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iptv_core/iptv_core.dart';

import '../sources/source_providers.dart';

/// Todo `watch_state` indexado por [ChannelRef] (S6, Bloque D) — para que
/// `SeriesDetailScreen` pinte la barra de progreso de cada episodio y
/// resuelva "Continuar T{n}E{n}" sin un `find()` por fila (mismo motivo
/// que `EpgNowController` agrupa en lotes en vez de consultar canal a
/// canal). Un `Map` completo es aceptable aquí — a diferencia de
/// `ChannelPageCache`, no hay 100k `WatchState` reales que paginar
/// (RNF-04 no aplica: son registros pequeños, uno por canal/episodio con
/// progreso real, nunca todo el catálogo).
final allWatchStatesProvider = FutureProvider<Map<ChannelRef, WatchState>>((ref) async {
  final states = await ref.watch(watchStateRepositoryProvider).getAll();
  return {for (final state in states) state.channel: state};
});
