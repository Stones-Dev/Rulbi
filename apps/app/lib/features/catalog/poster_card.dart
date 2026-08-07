import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_tokens/iptv_tokens.dart';

import '../../l10n/app_localizations.dart';
import '../../widgets/poster_fallback.dart';
import '../favorites/favorites_providers.dart';
import '../sources/source_providers.dart';

/// Ítem de la rejilla de Películas/Series (ui-spec §2.3.1): póster, título,
/// año (si el origen lo trae — solo el catálogo de series de Xtream lo
/// hace hoy, ver `XtreamMapper.seriesToChannel`, `x-xtream-release-date`),
/// badge de favorito. Mismo patrón de foco/favorito que `ChannelRow`
/// (`features/channels/channel_row.dart`), adaptado a póster en vez de
/// fila.
class PosterCard extends ConsumerStatefulWidget {
  const PosterCard({super.key, required this.channel, this.onTap});

  final Channel channel;
  final VoidCallback? onTap;

  @override
  ConsumerState<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends ConsumerState<PosterCard> {
  final FocusNode _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChange);
  }

  void _handleFocusChange() => setState(() => _focused = _focusNode.hasFocus);

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final channel = widget.channel;
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;

    final favoriteRefsAsync = ref.watch(favoriteRefsProvider);
    final isFavorite = favoriteRefsAsync.valueOrNull?.contains(channel.ref) ?? false;
    final year = _releaseYear(channel);

    return Focus(
      focusNode: _focusNode,
      child: InkWell(
        key: Key('posterCard.${channel.ref.serialized}'),
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.all(IptvSpacing.xs),
          decoration: BoxDecoration(
            border: _focused ? IptvFocus.ring() : null,
            boxShadow: _focused ? IptvFocus.haloShadow() : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(IptvSpacing.radius),
                      child: _Poster(channel: channel),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: IconButton(
                        key: Key('posterCard.favorite.${channel.ref.serialized}'),
                        tooltip: isFavorite ? l10n.favoriteRemoveTooltip : l10n.favoriteAddTooltip,
                        icon: Icon(
                          isFavorite ? Icons.favorite : Icons.favorite_border,
                          color: isFavorite ? IptvColors.accent : Colors.white,
                          shadows: const [Shadow(blurRadius: 4, color: Colors.black)],
                        ),
                        onPressed: () => ref.read(manageFavoritesProvider).toggle(channel.ref),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: IptvSpacing.xs),
              Text(
                channel.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodyMedium?.copyWith(color: IptvColors.textPrimary),
              ),
              if (year != null)
                Text(
                  year,
                  style: textTheme.bodySmall?.copyWith(color: IptvColors.textSecondary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Primeros 4 dígitos de `x-xtream-release-date` (`XtreamMapper
/// .seriesToChannel`), si empieza por un año plausible — nunca lanza ante
/// un formato inesperado, solo omite el año (mismo criterio RNF-09 que el
/// resto de metadatos opcionales: mejor sin dato que un dato inventado).
String? _releaseYear(Channel channel) {
  final raw = channel.metadata['x-xtream-release-date'];
  if (raw == null || raw.length < 4) return null;
  final year = raw.substring(0, 4);
  return int.tryParse(year) == null ? null : year;
}

class _Poster extends StatelessWidget {
  const _Poster({required this.channel});

  final Channel channel;

  @override
  Widget build(BuildContext context) {
    final logo = channel.logo;
    if (logo == null) return PosterFallback(name: channel.name);
    return CachedNetworkImage(
      imageUrl: logo.toString(),
      fit: BoxFit.cover,
      // 2x-ish el ancho típico de una celda de rejilla — nítido en
      // pantallas de alta densidad sin decodificar el bitmap a resolución
      // completa del origen (mismo criterio RNF-04 que `_ChannelLogo`).
      memCacheWidth: 400,
      placeholder: (_, _) => PosterFallback(name: channel.name),
      errorWidget: (_, _, _) => PosterFallback(name: channel.name),
    );
  }
}
