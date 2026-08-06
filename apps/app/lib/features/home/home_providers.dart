import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iptv_core/iptv_core.dart';

import '../sources/source_providers.dart';

/// Home desktop — fila "Continuar viendo" (ui-spec §2.2, S5 · Ola 1).
/// Sin invalidación automática todavía: no hay reproductor en este ola
/// que escriba en `watch_state`, así que no hace falta refrescar en
/// caliente — se recalcula al reconstruir el provider (p. ej. al volver
/// a Inicio).
final continueWatchingProvider = FutureProvider<List<ContinueWatchingItem>>((
  ref,
) {
  return ref.watch(getContinueWatchingProvider)();
});
