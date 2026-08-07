import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_tokens/iptv_tokens.dart';

import '../../l10n/app_localizations.dart';
import '../../widgets/poster_fallback.dart';

/// Fila "Favoritos" de Home (ui-spec §2.2, S5 · Ola 2) — de solo lectura:
/// el *drag* para reordenar vive en la sección Favoritos
/// (`FavoritesScreen`), no aquí (arrastrar entraría en conflicto con el
/// scroll horizontal de esta fila). Mismo patrón visual de tarjeta que
/// `ContinueWatchingRow` (Figma TV Shell), sin barra de progreso — un
/// favorito no tiene "cuánto queda".
class FavoritesRow extends StatelessWidget {
  const FavoritesRow({super.key, required this.channels, this.onTap});

  final List<Channel> channels;

  /// S6, Bloque E: mismo despacho por tipo que la sección Favoritos
  /// (`FavoritesScreen`, vía `openChannel`) — esta fila solo pinta, quien
  /// la construye decide qué hacer con el tap.
  final ValueChanged<Channel>? onTap;

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
              onTap: onTap == null ? null : () => onTap!(channels[index]),
            ),
          ),
        ),
      ],
    );
  }
}

class _FavoriteCard extends StatelessWidget {
  const _FavoriteCard({required this.channel, this.onTap});

  final Channel channel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final logo = channel.logo;

    return InkWell(
      key: Key('favoritesRow.${channel.ref.serialized}'),
      onTap: onTap,
      child: SizedBox(
        width: 174,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(IptvSpacing.radius),
          child: logo == null
              ? PosterFallback(name: channel.name, size: 174)
              : CachedNetworkImage(
                  imageUrl: logo.toString(),
                  width: 174,
                  height: 174,
                  fit: BoxFit.cover,
                  memCacheWidth: 348,
                  placeholder: (_, _) =>
                      PosterFallback(name: channel.name, size: 174),
                  errorWidget: (_, _, _) =>
                      PosterFallback(name: channel.name, size: 174),
                ),
        ),
      ),
    );
  }
}
