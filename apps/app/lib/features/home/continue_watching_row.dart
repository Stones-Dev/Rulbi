import 'package:flutter/material.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_tokens/iptv_tokens.dart';

import '../../l10n/app_localizations.dart';
import '../../widgets/media_card.dart';

/// Fila "Continuar viendo" (ui-spec §2.2, S5 · Ola 1) — tarjetas
/// `MediaCard` (S6.5, Implementación Desktop rediseñado): imagen a sangre
/// completa 220×124, título y barra de progreso superpuestos sobre el
/// degradado inferior, medidas del frame canónico `Desktop / Home` (`38:3`)
/// ya fusionado en Figma.
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
          height: MediaCard.height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: IptvSpacing.lg),
            itemBuilder: (context, index) {
              final item = items[index];
              final channel = item.channel;
              final isLive = item.duration == Duration.zero;

              return MediaCard(
                itemKey: Key('continueWatching.${channel.ref.serialized}'),
                imageUrl: channel.logo,
                fallbackLabel: channel.name,
                fallbackIcon: isLive ? Symbols.live_tv_rounded : Symbols.movie_rounded,
                title: channel.name,
                progress: isLive ? null : item.fraction,
                footer: isLive
                    ? null
                    : Text(
                        _remainingLabel(l10n, item.remaining),
                        style: IptvTypography.labelDesktop.copyWith(color: IptvColors.textSecondary),
                      ),
                onTap: onTap == null ? null : () => onTap!(item),
              );
            },
          ),
        ),
      ],
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
