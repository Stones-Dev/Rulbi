import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_tokens/iptv_tokens.dart';

import '../../l10n/app_localizations.dart';

/// Fila "Continuar viendo" (ui-spec §2.2, S5 · Ola 1) — adaptada del nodo
/// Figma `Row/ContinuarViendo` (archivo `2nrXvhb5FRPmvWNznb2tQw`, página
/// *TV Shell*): tarjetas 310×236 a densidad TV, con póster 310×174, barra
/// de progreso de 6 px al pie, título y tiempo restante.
class ContinueWatchingRow extends StatelessWidget {
  const ContinueWatchingRow({super.key, required this.items, this.onTap});

  final List<ContinueWatchingItem> items;

  /// S6, Bloque E: siempre reanuda directo en el reproductor (nunca una
  /// ficha) — a diferencia de `FavoritesRow`, todo lo que aparece aquí es
  /// por definición ya reproducible (tiene `WatchState` real), incluido
  /// un episodio de serie (`Channel.type == series` pero apuntando al
  /// episodio, no al catálogo de la serie).
  final ValueChanged<ContinueWatchingItem>? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.homeContinueWatchingTitle,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: IptvSpacing.md),
        SizedBox(
          height: 236,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: IptvSpacing.lg),
            itemBuilder: (context, index) => _ContinueWatchingCard(
              item: items[index],
              onTap: onTap == null ? null : () => onTap!(items[index]),
            ),
          ),
        ),
      ],
    );
  }
}

class _ContinueWatchingCard extends StatelessWidget {
  const _ContinueWatchingCard({required this.item, this.onTap});

  final ContinueWatchingItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final channel = item.channel;
    final isLive = item.duration == Duration.zero;

    return InkWell(
      key: Key('continueWatching.${channel.ref.serialized}'),
      onTap: onTap,
      child: SizedBox(
        width: 310,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Poster(channel: channel, fraction: isLive ? null : item.fraction),
            const SizedBox(height: IptvSpacing.sm),
            Text(
              channel.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (!isLive) ...[
              const SizedBox(height: 4),
              Text(
                _remainingLabel(l10n, item.remaining),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: IptvColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _remainingLabel(AppLocalizations l10n, Duration remaining) {
    final totalMinutes = remaining.inMinutes.clamp(0, 1 << 30);
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours > 0) return l10n.homeRemainingHoursMinutes(hours, minutes);
    return l10n.homeRemainingMinutes(minutes);
  }
}

class _Poster extends StatelessWidget {
  const _Poster({required this.channel, required this.fraction});

  final Channel channel;

  /// `null` para directo: sin barra de progreso (no hay "cuánto queda"
  /// que mostrar).
  final double? fraction;

  @override
  Widget build(BuildContext context) {
    final logo = channel.logo;

    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(IptvSpacing.radius),
          child: logo == null
              ? _PosterFallback(name: channel.name)
              : CachedNetworkImage(
                  imageUrl: logo.toString(),
                  width: 310,
                  height: 174,
                  fit: BoxFit.cover,
                  memCacheWidth: 620,
                  placeholder: (_, _) => _PosterFallback(name: channel.name),
                  errorWidget: (_, _, _) => _PosterFallback(name: channel.name),
                ),
        ),
        if (fraction != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(IptvSpacing.radius),
              ),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 6,
                backgroundColor: IptvColors.border,
                valueColor: const AlwaysStoppedAnimation(IptvColors.accent),
              ),
            ),
          ),
      ],
    );
  }
}

class _PosterFallback extends StatelessWidget {
  const _PosterFallback({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 310,
      height: 174,
      alignment: Alignment.center,
      color: IptvColors.surface,
      child: Icon(
        Icons.movie_outlined,
        size: 40,
        color: IptvColors.textSecondary,
        semanticLabel: name,
      ),
    );
  }
}
