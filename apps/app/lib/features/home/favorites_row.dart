import 'package:flutter/material.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_tokens/iptv_tokens.dart';

import '../../l10n/app_localizations.dart';
import '../../widgets/media_card.dart';

/// Fila "Favoritos" de Home (ui-spec §2.2, S5 · Ola 2) — de solo lectura:
/// el *drag* para reordenar vive en la sección Favoritos
/// (`FavoritesScreen`), no aquí (arrastrar entraría en conflicto con el
/// scroll horizontal de esta fila).
///
/// S6.5 (Implementación Desktop rediseñado): mismo `MediaCard` que
/// `ContinueWatchingRow` — el frame canónico `38:3` ya fusionado en Figma
/// muestra tarjetas 220×124 con título superpuesto también en esta fila,
/// a diferencia del recorte cuadrado 174×174 sin título de antes de S6.5.
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
          height: MediaCard.height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: channels.length,
            separatorBuilder: (_, _) => const SizedBox(width: IptvSpacing.lg),
            itemBuilder: (context, index) {
              final channel = channels[index];
              return MediaCard(
                itemKey: Key('favoritesRow.${channel.ref.serialized}'),
                imageUrl: channel.logo,
                fallbackLabel: channel.name,
                title: channel.name,
                // Mismo string que `itemKey.value` — `openChannel`
                // propaga este tag hasta `VodDetailScreen`/
                // `SeriesDetailScreen` (S6.5 paso 7e).
                heroTag: 'favoritesRow.${channel.ref.serialized}',
                onTap: onTap == null ? null : () => onTap!(channel),
              );
            },
          ),
        ),
      ],
    );
  }
}
