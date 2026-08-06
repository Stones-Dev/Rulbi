import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iptv_core/iptv_core.dart';

import '../sources/source_providers.dart';

/// Fuentes que deben contribuir al listado/búsqueda (S5 · Ola 1, ui-spec
/// §2.3: "fuente desactivada (oculta)"). `sourcesStreamProvider` ya
/// excluye las tumbadas; aquí se filtra además por `enabled` — la regla
/// de "ocultar" vive en la app, `ChannelRepository`/`ChannelQuery` solo
/// reciben el conjunto ya resuelto (ver docstring de `ChannelQuery`).
final activeSourceIdsProvider = Provider<Set<String>>((ref) {
  final sourcesAsync = ref.watch(sourcesStreamProvider);
  return sourcesAsync.maybeWhen(
    data: (sources) => {for (final s in sources) if (s.enabled) s.id},
    orElse: () => const {},
  );
});

/// Panel de categorías con contador (ui-spec §2.3). `family` sobre
/// `ChannelQuery` (implementa `==`/`hashCode`) para que Riverpod cachee
/// por sección/fuentes activas sin recalcular en cada rebuild.
final categoriesWithCountProvider =
    FutureProvider.family<List<CategoryWithCount>, ChannelQuery>((
      ref,
      query,
    ) {
      return ref.watch(channelRepositoryProvider).categoriesWithCount(query);
    });

/// Total de canales vivos de [query] sin filtrar por categoría — para el
/// contador de la pseudo-categoría "Todas", que debe incluir también los
/// canales sin categoría asignada (`categoriesWithCount` no los cuenta,
/// ver su docstring).
final totalChannelCountProvider = FutureProvider.family<int, ChannelQuery>((
  ref,
  query,
) {
  return ref.watch(channelRepositoryProvider).countChannels(query);
});
