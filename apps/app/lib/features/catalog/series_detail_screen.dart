import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_protocols/iptv_protocols.dart';
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

/// Detalle de serie completo (ui-spec §2.7, S6, Bloque D) — cabecera igual
/// que [VodDetailScreen] + selector de temporada + lista de episodios con
/// progreso, y la acción destacada "Continuar T{n}E{n}". Reemplaza el
/// detalle mínimo interino de S5.5.
///
/// `ConsumerStatefulWidget` (no `ConsumerWidget`): necesita estado propio
/// para la temporada seleccionada — mismo criterio que `CatalogScreen`
/// con `_selectedCategoryId`.
class SeriesDetailScreen extends ConsumerStatefulWidget {
  const SeriesDetailScreen({super.key, required this.channel, this.heroTag});

  final Channel channel;

  /// Ver docstring de `VodDetailScreen.heroTag` — mismo propósito. Cableado
  /// al `DetailHero` en el paso 8 (S6.5); el constructor lo acepta ya
  /// desde el paso 7e para que `openChannel` pueda propagarlo sin esperar
  /// a que la ficha de serie tenga su propio rediseño.
  final String? heroTag;

  @override
  ConsumerState<SeriesDetailScreen> createState() => _SeriesDetailScreenState();
}

class _SeriesDetailScreenState extends ConsumerState<SeriesDetailScreen> {
  int? _selectedSeason;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final channel = widget.channel;

    final info = ref.watch(seriesInfoProvider(channel)).valueOrNull;
    final favoriteRefsAsync = ref.watch(favoriteRefsProvider);
    final isFavorite = favoriteRefsAsync.valueOrNull?.contains(channel.ref) ?? false;
    final watchStates = ref.watch(allWatchStatesProvider).valueOrNull ?? const <ChannelRef, WatchState>{};

    final title = (info?.info.name.isNotEmpty ?? false) ? info!.info.name : channel.name;
    final genre = info?.info.genre ?? channel.metadata['x-xtream-genre'];
    final ratingValue = info?.info.rating;
    final rating = ratingValue != null && ratingValue > 0
        ? ratingValue.toStringAsFixed(1)
        : channel.metadata['x-xtream-rating'];
    final plot = info?.info.plot ?? channel.metadata['x-xtream-plot'];
    final coverUrl = (info?.info.coverUrl != null ? Uri.tryParse(info!.info.coverUrl!) : null) ?? channel.logo;

    final seriesId = int.tryParse(channel.metadata['x-xtream-series-id'] ?? '') ?? 0;
    final episodesBySeason = <int, List<XtreamEpisode>>{
      for (final entry in (info?.episodesBySeason ?? const <int, List<XtreamEpisode>>{}).entries)
        entry.key: [...entry.value]..sort((a, b) => a.episodeNum.compareTo(b.episodeNum)),
    };
    final channelsBySeason = <int, List<Channel>>{
      for (final entry in episodesBySeason.entries)
        entry.key: [
          for (final episode in entry.value)
            XtreamMapper.episodeToChannel(
              sourceId: channel.sourceId,
              seriesId: seriesId,
              seasonNumber: entry.key,
              episode: episode,
            ),
        ],
    };
    final seasons = episodesBySeason.keys.toList()..sort();

    final continueTarget = _findContinueTarget(episodesBySeason, channelsBySeason, watchStates);

    final selectedSeason = seasons.contains(_selectedSeason) ? _selectedSeason : (seasons.isNotEmpty ? seasons.first : null);
    final episodesForSelected = selectedSeason != null ? episodesBySeason[selectedSeason]! : const <XtreamEpisode>[];
    final channelsForSelected = selectedSeason != null ? channelsBySeason[selectedSeason]! : const <Channel>[];

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(IptvSpacing.lg),
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
          Row(
            children: [
              if (continueTarget != null)
                ElevatedButton.icon(
                  key: const Key('seriesDetail.continue'),
                  onPressed: () => openPlayer(
                    context,
                    ref,
                    PlaybackRequest(
                      channel: continueTarget.channel,
                      startAt: continueTarget.startAt,
                      queue: PlaybackQueue(
                        items: channelsBySeason[continueTarget.season]!,
                        index: continueTarget.queueIndex,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(
                    l10n.seriesDetailContinueEpisode(continueTarget.season, continueTarget.episodeNumber),
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
          if (seasons.length > 1) ...[
            const SizedBox(height: IptvSpacing.lg),
            DropdownButton<int>(
              key: const Key('seriesDetail.seasonSelector'),
              value: selectedSeason,
              items: [
                for (final season in seasons)
                  DropdownMenuItem(value: season, child: Text(l10n.seriesDetailSeasonLabel(season))),
              ],
              onChanged: (season) => setState(() => _selectedSeason = season),
            ),
          ],
          const SizedBox(height: IptvSpacing.md),
          for (var i = 0; i < episodesForSelected.length; i++)
            _EpisodeRow(
              episode: episodesForSelected[i],
              channel: channelsForSelected[i],
              watchState: watchStates[channelsForSelected[i].ref],
              onTap: () => openPlayer(
                context,
                ref,
                PlaybackRequest(
                  channel: channelsForSelected[i],
                  startAt: watchStates[channelsForSelected[i].ref]?.position ?? Duration.zero,
                  queue: PlaybackQueue(items: channelsForSelected, index: i),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Episodio destacado de "Continuar T{n}E{n}" (ui-spec §2.7): el que
  /// tiene el `WatchState` sin terminar más reciente, buscando en **todas**
  /// las temporadas (no solo la seleccionada) — un episodio a medias de la
  /// temporada 1 debe destacarse aunque el usuario esté viendo la ficha con
  /// la temporada 3 abierta. Sin ningún progreso real, cae a T{primera
  /// temporada}E1 (ui-spec no lo dice explícitamente, pero sin esto el
  /// botón "Continuar" no tendría a dónde apuntar en una serie nunca vista).
  _ContinueTarget? _findContinueTarget(
    Map<int, List<XtreamEpisode>> episodesBySeason,
    Map<int, List<Channel>> channelsBySeason,
    Map<ChannelRef, WatchState> watchStates,
  ) {
    WatchState? best;
    int? bestSeason;
    int? bestIndex;

    for (final season in episodesBySeason.keys) {
      final channels = channelsBySeason[season]!;
      for (var i = 0; i < channels.length; i++) {
        final state = watchStates[channels[i].ref];
        if (state == null || state.isFinished || state.position <= Duration.zero) continue;
        if (best == null || state.updatedAt.isAfter(best.updatedAt)) {
          best = state;
          bestSeason = season;
          bestIndex = i;
        }
      }
    }

    if (best != null && bestSeason != null && bestIndex != null) {
      return _ContinueTarget(
        season: bestSeason,
        episodeNumber: episodesBySeason[bestSeason]![bestIndex].episodeNum,
        channel: channelsBySeason[bestSeason]![bestIndex],
        queueIndex: bestIndex,
        startAt: best.position,
      );
    }

    final seasons = episodesBySeason.keys.toList()..sort();
    if (seasons.isEmpty) return null;
    final firstSeason = seasons.first;
    final episodes = episodesBySeason[firstSeason]!;
    if (episodes.isEmpty) return null;
    return _ContinueTarget(
      season: firstSeason,
      episodeNumber: episodes.first.episodeNum,
      channel: channelsBySeason[firstSeason]!.first,
      queueIndex: 0,
      startAt: Duration.zero,
    );
  }
}

final class _ContinueTarget {
  const _ContinueTarget({
    required this.season,
    required this.episodeNumber,
    required this.channel,
    required this.queueIndex,
    required this.startAt,
  });

  final int season;
  final int episodeNumber;
  final Channel channel;
  final int queueIndex;
  final Duration startAt;
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({
    required this.episode,
    required this.channel,
    required this.watchState,
    required this.onTap,
  });

  final XtreamEpisode episode;
  final Channel channel;
  final WatchState? watchState;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final duration = episode.durationSecs != null ? Duration(seconds: episode.durationSecs!) : null;
    final fraction = watchState != null && !watchState!.isFinished ? watchState!.fraction : null;

    return InkWell(
      key: Key('seriesDetail.episode.${channel.ref.serialized}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: IptvSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 32,
              child: Text('${episode.episodeNum}', style: textTheme.bodyLarge),
            ),
            const SizedBox(width: IptvSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(episode.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: textTheme.bodyLarge),
                  if (fraction != null && fraction > 0) ...[
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: fraction,
                        minHeight: 3,
                        backgroundColor: IptvColors.border,
                        valueColor: const AlwaysStoppedAnimation(IptvColors.accent),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (duration != null) ...[
              const SizedBox(width: IptvSpacing.sm),
              Text(
                formatDurationShort(duration),
                style: textTheme.bodySmall?.copyWith(color: IptvColors.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
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
