import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iptv_core/iptv_core.dart';

import '../sources/source_providers.dart';

/// Pertenencia a favoritos, para el badge de `ChannelRow` (S5 · Ola 2,
/// ui-spec §2.3) — un `Set<ChannelRef>` en vez de mirar `Favorite` fila a
/// fila: cada fila del listado solo necesita "¿está o no?", `O(1)` por
/// fila en vez de una consulta por fila.
final favoriteRefsProvider = StreamProvider<Set<ChannelRef>>((ref) {
  return ref
      .watch(favoritesRepositoryProvider)
      .watchAll()
      .map((favorites) => {for (final f in favorites) if (!f.isDeleted) f.channel});
});

/// Favoritos vivos, ya hidratados a `Channel` completo y en el orden
/// manual del usuario (`FavoritesRepository.watchAll` ya ordena por
/// `sortOrder`, ver `DriftFavoritesRepository`) — usado por la fila de
/// solo lectura de Home y por la sección Favoritos con reordenación.
///
/// Un `ChannelRef` cuyo canal ya no existe (fuente borrada) simplemente no
/// aparece — mismo criterio que `GetContinueWatching`.
final favoritesListProvider = StreamProvider<List<Channel>>((ref) {
  final channels = ref.watch(channelRepositoryProvider);
  return ref.watch(favoritesRepositoryProvider).watchAll().asyncMap((
    favorites,
  ) async {
    final alive = [
      for (final f in favorites)
        if (!f.isDeleted) f,
    ];
    final hydrated = await channels.findByRefs([
      for (final f in alive) f.channel,
    ]);
    final byRef = {for (final c in hydrated) c.ref: c};
    return [for (final f in alive) ?byRef[f.channel]];
  });
});
