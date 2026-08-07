import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_tokens/iptv_tokens.dart';

import '../../l10n/app_localizations.dart';

/// Fila "Favoritos" de Home (ui-spec §2.2, S5 · Ola 2) — de solo lectura:
/// el *drag* para reordenar vive en la sección Favoritos
/// (`FavoritesScreen`), no aquí (arrastrar entraría en conflicto con el
/// scroll horizontal de esta fila). Mismo patrón visual de tarjeta que
/// `ContinueWatchingRow` (Figma TV Shell), sin barra de progreso — un
/// favorito no tiene "cuánto queda".
class FavoritesRow extends StatelessWidget {
  const FavoritesRow({super.key, required this.channels});

  final List<Channel> channels;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.homeFavoritesTitle,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: IptvSpacing.md),
        SizedBox(
          height: 174,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: channels.length,
            separatorBuilder: (_, _) => const SizedBox(width: IptvSpacing.lg),
            itemBuilder: (context, index) => _FavoriteCard(
              channel: channels[index],
            ),
          ),
        ),
      ],
    );
  }
}

class _FavoriteCard extends StatelessWidget {
  const _FavoriteCard({required this.channel});

  final Channel channel;

  @override
  Widget build(BuildContext context) {
    final logo = channel.logo;

    return SizedBox(
      key: Key('favoritesRow.${channel.ref.serialized}'),
      width: 174,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(IptvSpacing.radius),
        child: logo == null
            ? _PosterFallback(name: channel.name)
            : CachedNetworkImage(
                imageUrl: logo.toString(),
                width: 174,
                height: 174,
                fit: BoxFit.cover,
                memCacheWidth: 348,
                placeholder: (_, _) => _PosterFallback(name: channel.name),
                errorWidget: (_, _, _) => _PosterFallback(name: channel.name),
              ),
      ),
    );
  }
}

class _PosterFallback extends StatelessWidget {
  const _PosterFallback({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 174,
      height: 174,
      alignment: Alignment.center,
      color: IptvColors.surface,
      padding: const EdgeInsets.all(IptvSpacing.sm),
      child: Text(
        name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(color: IptvColors.textSecondary),
      ),
    );
  }
}
