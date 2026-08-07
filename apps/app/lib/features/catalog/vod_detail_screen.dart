import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_tokens/iptv_tokens.dart';

import '../../l10n/app_localizations.dart';
import '../../widgets/duration_format.dart';
import '../../widgets/poster_fallback.dart';
import '../favorites/favorites_providers.dart';
import '../player/open_player.dart';
import '../player/playback_request.dart';
import '../sources/source_providers.dart';
import 'catalog_info_providers.dart';
import 'watch_state_providers.dart';

/// Detalle VOD completo (ui-spec §2.6, S6, Bloque D) — reemplaza el
/// detalle mínimo interino de S5.5 (`ContentDetailScreen`, eliminado en
/// esta ola): póster, título, año, duración, género, rating y sinopsis,
/// todos opcionales con fallback tipográfico digno cuando `vodInfoProvider`
/// no tiene ficha (fuente M3U, sin credencial, o panel caído) — en ese
/// caso se degrada exactamente a lo que ya pintaba `ContentDetailScreen`:
/// los metadatos planos que el mapper de Xtream adjunta al importar
/// (`x-xtream-*`), nunca un error.
class VodDetailScreen extends ConsumerWidget {
  const VodDetailScreen({super.key, required this.channel});

  final Channel channel;

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
    final durationMinutes = info?.durationSecs != null ? (info!.durationSecs! / 60).round() : null;
    final coverUrl = (info?.coverUrl != null ? Uri.tryParse(info!.coverUrl!) : null) ?? channel.logo;

    final hasProgress = watchState != null && !watchState.isFinished && watchState.position > Duration.zero;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
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
                  child: _Poster(name: title, coverUrl: coverUrl),
                ),
              ),
            ),
            const SizedBox(height: IptvSpacing.lg),
            Text(title, style: textTheme.headlineSmall),
            if (year != null || durationMinutes != null || genre != null || rating != null) ...[
              const SizedBox(height: IptvSpacing.xs),
              Text(
                [
                  ?year,
                  if (durationMinutes != null) l10n.vodDetailDurationMinutes(durationMinutes),
                  ?genre,
                  if (rating != null) '★ $rating',
                ].join('  ·  '),
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
                ElevatedButton.icon(
                  key: const Key('vodDetail.play'),
                  onPressed: () => openPlayer(
                    context,
                    ref,
                    PlaybackRequest(
                      channel: channel,
                      startAt: hasProgress ? watchState.position : Duration.zero,
                    ),
                  ),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(
                    hasProgress
                        ? l10n.contentDetailContinueAction(formatDurationShort(watchState.position))
                        : l10n.contentDetailPlayAction,
                  ),
                ),
                const SizedBox(width: IptvSpacing.md),
                OutlinedButton.icon(
                  key: Key('contentDetail.favorite.${channel.ref.serialized}'),
                  onPressed: () => ref.read(manageFavoritesProvider).toggle(channel.ref),
                  icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border),
                  label: Text(isFavorite ? l10n.favoriteRemoveTooltip : l10n.favoriteAddTooltip),
                ),
              ],
            ),
          ],
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

class _Poster extends StatelessWidget {
  const _Poster({required this.name, required this.coverUrl});

  final String name;
  final Uri? coverUrl;

  @override
  Widget build(BuildContext context) {
    final url = coverUrl;
    if (url == null) return PosterFallback(name: name);
    return CachedNetworkImage(
      imageUrl: url.toString(),
      fit: BoxFit.cover,
      memCacheWidth: 480,
      placeholder: (_, _) => PosterFallback(name: name),
      errorWidget: (_, _, _) => PosterFallback(name: name),
    );
  }
}
