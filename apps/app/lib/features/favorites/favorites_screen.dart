import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_tokens/iptv_tokens.dart';

import '../../l10n/app_localizations.dart';
import '../channels/channel_row.dart';
import '../epg/epg_providers.dart';
import '../player/open_channel.dart';
import '../player/playback_request.dart';
import '../sources/source_providers.dart';
import 'favorites_providers.dart';

/// Sección Favoritos (ui-spec §2.2/§2.3, S5 · Ola 2): reordenación manual
/// por *drag* — persiste de verdad (`ManageFavorites.reorder`, columna
/// `sortOrder`), no en memoria. Reutiliza `ChannelRow` tal cual (mismo
/// badge de favorito, mismo subtítulo EPG que el listado de canales): esta
/// pantalla no es un tipo de fila distinto, es el mismo listado filtrado a
/// solo favoritos y con orden manual.
///
/// `ConsumerStatefulWidget`, no `ConsumerWidget` — necesita dueño y ciclo
/// de vida propios para `EpgNowController` (una instancia por pantalla,
/// mismo criterio que `ChannelListScreen`), no algo que Riverpod pueda
/// reconstruir sin más en cada rebuild.
class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen> {
  late final EpgNowController _epgController;

  @override
  void initState() {
    super.initState();
    _epgController = createEpgNowController(ref);
  }

  @override
  void dispose() {
    _epgController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final favoritesAsync = ref.watch(favoritesListProvider);

    return favoritesAsync.when(
      data: (channels) => channels.isEmpty
          ? _EmptyFavorites(l10n: l10n)
          : _FavoritesList(channels: channels, epgController: _epgController),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => Center(child: Text(l10n.probeErrorUnknown)),
    );
  }
}

class _FavoritesList extends ConsumerWidget {
  const _FavoritesList({required this.channels, required this.epgController});

  final List<Channel> channels;
  final EpgNowController epgController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `ReorderableListView` (no una implementación de drag propia): trae
    // el handle de arrastre y la semántica de accesibilidad ya resueltos,
    // y se adapta sola por plataforma (icono de agarre en desktop/web,
    // long-press en touch) — RNF-11/P9, sin coste de mantenimiento propio.
    return ReorderableListView.builder(
      key: const Key('favoritesList'),
      padding: const EdgeInsets.symmetric(vertical: IptvSpacing.sm),
      itemExtent: channelRowExtent,
      itemCount: channels.length,
      onReorderItem: (oldIndex, newIndex) {
        // `newIndex` ya viene ajustado (Flutter descuenta el hueco que
        // deja el elemento movido antes de llamar a este callback) — a
        // diferencia del `onReorder` obsoleto, aquí no hace falta el
        // `newIndex > oldIndex ? newIndex - 1 : newIndex` manual.
        final refs = channels.map((c) => c.ref).toList();
        final moved = refs.removeAt(oldIndex);
        refs.insert(newIndex, moved);
        // `ManageFavorites.reorder` ya reindexa 0..n-1 y persiste con
        // `updated_at` — el nuevo orden llega de vuelta por el propio
        // `watchAll()` reactivo (`favoritesListProvider`), no hace falta
        // estado local optimista.
        unawaited(ref.read(manageFavoritesProvider).reorder(refs));
      },
      itemBuilder: (context, index) {
        final channel = channels[index];
        return ChannelRow(
          key: Key('channelRow.${channel.ref.serialized}'),
          channel: channel,
          epgController: epgController,
          // S6, Bloque E: Favoritos mezcla directo/VOD/series (a
          // diferencia de CatalogScreen) — `openChannel` despacha por
          // tipo. Zapping ↑/↓ solo entre los favoritos en directo: no
          // tiene sentido "siguiente canal" saltando a una película.
          onTap: () {
            final liveChannels = channels.where((c) => c.type == ContentType.live).toList();
            final liveIndex = liveChannels.indexOf(channel);
            openChannel(
              context,
              ref,
              channel,
              queue: liveIndex < 0
                  ? null
                  : PlaybackQueue(items: liveChannels, index: liveIndex),
            );
          },
        );
      },
    );
  }
}

class _EmptyFavorites extends StatelessWidget {
  const _EmptyFavorites({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.favorite_border,
            size: 64,
            color: IptvColors.textSecondary,
          ),
          const SizedBox(height: IptvSpacing.md),
          Text(
            l10n.favoritesEmptyTitle,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: IptvSpacing.sm),
          Text(l10n.favoritesEmptyHint, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
