import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_tokens/iptv_tokens.dart';

import '../../l10n/app_localizations.dart';
import '../../widgets/poster_fallback.dart';
import '../favorites/favorites_providers.dart';
import '../sources/source_providers.dart';

/// Detalle mínimo de un ítem del catálogo (S5.5, Bloque D4) — abierto al
/// tocar un `PosterCard`. **No** es §2.6 Detalle VOD / §2.7 Detalle de
/// serie completas: eso pide `get_vod_info`/`get_series_info` bajo demanda
/// (año, duración, género, rating, sinopsis; selector de temporada +
/// episodios), fuera de alcance de este sprint — ver plan de S5.5. Aquí
/// solo se muestra lo que ya trae `Channel` desde el import (póster,
/// nombre, y los metadatos planos que el mapper de Xtream ya adjunta,
/// `x-xtream-*`), más el toggle de favorito.
///
/// Empujada con el `Navigator` raíz que ya provee `MaterialApp`
/// (`Navigator.of(context).push`, mismo patrón que `ImportScreen`/los
/// formularios de fuente en `sources_screen.dart`) — no hace falta un
/// `Navigator` propio.
class ContentDetailScreen extends ConsumerWidget {
  const ContentDetailScreen({super.key, required this.channel});

  final Channel channel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;

    final favoriteRefsAsync = ref.watch(favoriteRefsProvider);
    final isFavorite = favoriteRefsAsync.valueOrNull?.contains(channel.ref) ?? false;

    final genre = channel.metadata['x-xtream-genre'];
    final rating = channel.metadata['x-xtream-rating'];
    final plot = channel.metadata['x-xtream-plot'];

    return Scaffold(
      appBar: AppBar(title: Text(channel.name)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(IptvSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: SizedBox(
                width: 240,
                height: 360,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(IptvSpacing.radius),
                  child: _DetailPoster(channel: channel),
                ),
              ),
            ),
            const SizedBox(height: IptvSpacing.lg),
            Text(channel.name, style: textTheme.headlineSmall),
            if (genre != null || rating != null) ...[
              const SizedBox(height: IptvSpacing.xs),
              Text(
                [?genre, if (rating != null) '★ $rating'].join('  ·  '),
                style: textTheme.bodyMedium?.copyWith(color: IptvColors.textSecondary),
              ),
            ],
            if (plot != null) ...[
              const SizedBox(height: IptvSpacing.md),
              Text(plot, style: textTheme.bodyMedium),
            ],
            const SizedBox(height: IptvSpacing.lg),
            OutlinedButton.icon(
              key: Key('contentDetail.favorite.${channel.ref.serialized}'),
              onPressed: () => ref.read(manageFavoritesProvider).toggle(channel.ref),
              icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border),
              label: Text(isFavorite ? l10n.favoriteRemoveTooltip : l10n.favoriteAddTooltip),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailPoster extends StatelessWidget {
  const _DetailPoster({required this.channel});

  final Channel channel;

  @override
  Widget build(BuildContext context) {
    final logo = channel.logo;
    if (logo == null) return PosterFallback(name: channel.name);
    return CachedNetworkImage(
      imageUrl: logo.toString(),
      fit: BoxFit.cover,
      memCacheWidth: 480,
      placeholder: (_, _) => PosterFallback(name: channel.name),
      errorWidget: (_, _, _) => PosterFallback(name: channel.name),
    );
  }
}
