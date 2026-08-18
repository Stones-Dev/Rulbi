import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_tokens/iptv_tokens.dart';

import '../../l10n/app_localizations.dart';
import '../../widgets/detail_hero.dart';
import '../../widgets/duration_format.dart';
import '../../widgets/favorite_bounce_button.dart';
import '../favorites/favorites_providers.dart';
import '../player/open_player.dart';
import '../player/playback_request.dart';
import '../sources/source_providers.dart';
import 'catalog_info_providers.dart';
import 'watch_state_providers.dart';

/// Detalle VOD completo (ui-spec §2.6, S6, Bloque D; rediseñado S6.5 paso
/// 7 sobre el frame Figma `43:2`) — reemplaza el detalle mínimo interino
/// de S5.5 (`ContentDetailScreen`, eliminado en esa ola): backdrop +
/// póster ([DetailHero]), título, año, duración, género, rating y
/// sinopsis, todos opcionales con fallback tipográfico digno cuando
/// `vodInfoProvider` no tiene ficha (fuente M3U, sin credencial, o panel
/// caído) — en ese caso se degrada exactamente a lo que ya pintaba
/// `ContentDetailScreen`: los metadatos planos que el mapper de Xtream
/// adjunta al importar (`x-xtream-*`), nunca un error.
class VodDetailScreen extends ConsumerWidget {
  const VodDetailScreen({super.key, required this.channel, this.heroTag});

  final Channel channel;

  /// Propagado por el llamador (`MediaCard`/`PosterCard`, paso 7e) para
  /// que el póster haga una transición `Hero` desde su fila de origen.
  /// `null` no envuelve el póster en `Hero`.
  final String? heroTag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;

    final info = ref.watch(vodInfoProvider(channel)).valueOrNull;
    final favoriteRefsAsync = ref.watch(favoriteRefsProvider);
    final isFavorite = favoriteRefsAsync.valueOrNull?.contains(channel.ref) ?? false;
    final watchState = ref.watch(allWatchStatesProvider).valueOrNull?[channel.ref];

    final title = (info?.name.isNotEmpty ?? false) ? info!.name : channel.name;
    final year = _yearOf(info?.releaseDate ?? channel.metadata['x-xtream-release-date']);
    final genre = info?.genre ?? channel.metadata['x-xtream-genre'];
    final ratingValue = info?.rating;
    final rating = ratingValue != null && ratingValue > 0
        ? ratingValue.toStringAsFixed(1)
        : channel.metadata['x-xtream-rating'];
    final plot = info?.plot ?? channel.metadata['x-xtream-plot'];
    final durationLabel = info?.durationSecs != null
        ? formatDurationHoursMinutes(l10n, Duration(seconds: info!.durationSecs!))
        : null;
    final coverUrl = info?.coverUrl ?? channel.logo?.toString();

    final hasProgress = watchState != null && !watchState.isFinished && watchState.position > Duration.zero;

    return Scaffold(
      body: SingleChildScrollView(
        child: DetailHero(
          title: title,
          backdropUrl: info?.backdropUrl,
          coverUrl: coverUrl,
          backdropHeight: 480,
          posterWidth: 180,
          posterHeight: 260,
          posterOverlap: 60,
          heroTag: heroTag,
          content: Padding(
            padding: const EdgeInsets.symmetric(horizontal: IptvSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: textTheme.headlineMedium),
                if (year != null || durationLabel != null || genre != null || rating != null) ...[
                  const SizedBox(height: IptvSpacing.xs),
                  Text(
                    [?year, ?durationLabel, ?genre, if (rating != null) '★ $rating'].join('  ·  '),
                    style: textTheme.bodyMedium?.copyWith(color: IptvColors.textSecondary),
                  ),
                ],
                if (plot != null) ...[
                  const SizedBox(height: IptvSpacing.md),
                  Text(plot, style: textTheme.bodyMedium),
                ],
                const SizedBox(height: IptvSpacing.lg),
                Row(
                  children: [
                    FilledButton.icon(
                      key: const Key('vodDetail.play'),
                      onPressed: () => openPlayer(
                        context,
                        ref,
                        PlaybackRequest(
                          channel: channel,
                          startAt: hasProgress ? watchState.position : Duration.zero,
                        ),
                      ),
                      icon: const Icon(Symbols.play_arrow_rounded),
                      label: Text(
                        hasProgress
                            ? l10n.contentDetailContinueAction(formatDurationShort(watchState.position))
                            : l10n.contentDetailPlayAction,
                      ),
                    ),
                    const SizedBox(width: IptvSpacing.md),
                    FavoriteBounceButton(
                      itemKey: Key('contentDetail.favorite.${channel.ref.serialized}'),
                      isFavorite: isFavorite,
                      tooltip: isFavorite ? l10n.favoriteRemoveTooltip : l10n.favoriteAddTooltip,
                      onPressed: () => ref.read(manageFavoritesProvider).toggle(channel.ref),
                    ),
                  ],
                ),
                const SizedBox(height: IptvSpacing.xl),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Acepta `YYYY-MM-DD`, `YYYY` suelto, o cualquier string que empiece
  /// por 4 dígitos — dialecto tolerante, igual de laxo que el resto del
  /// mapeo Xtream (`asFlexibleString` en `protocols`): un año mal
  /// formado se omite, nunca revienta la ficha.
  static String? _yearOf(String? raw) {
    if (raw == null || raw.length < 4) return null;
    final year = raw.substring(0, 4);
    return int.tryParse(year) != null ? year : null;
  }
}
