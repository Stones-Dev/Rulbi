import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_protocols/iptv_protocols.dart';
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

/// Detalle de serie completo (ui-spec §2.7, S6, Bloque D; rediseñado
/// S6.5 paso 8 sobre el frame Figma `44:2`) — cabecera igual que
/// [VodDetailScreen] ([DetailHero]) + chips de temporada (`44:11`) +
/// lista de episodios con miniatura real (`XtreamEpisode.stillUrl`,
/// campo añadido en el paso 2 de esta misma tarea, sin consumidor hasta
/// ahora) y progreso, y la acción destacada "Continuar T{n}E{n}".
///
/// `ConsumerStatefulWidget` (no `ConsumerWidget`): necesita estado propio
/// para la temporada seleccionada — mismo criterio que `CatalogScreen`
/// con `_selectedCategoryId`.
class SeriesDetailScreen extends ConsumerStatefulWidget {
  const SeriesDetailScreen({super.key, required this.channel, this.heroTag});

  final Channel channel;

  /// Ver docstring de `VodDetailScreen.heroTag` — mismo propósito (S6.5
  /// paso 7e), cableado al `DetailHero` aquí en el paso 8.
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
    final year = _yearOf(info?.info.releaseDate);
    final genre = info?.info.genre ?? channel.metadata['x-xtream-genre'];
    final ratingValue = info?.info.rating;
    final rating = ratingValue != null && ratingValue > 0
        ? ratingValue.toStringAsFixed(1)
        : channel.metadata['x-xtream-rating'];
    final plot = info?.info.plot ?? channel.metadata['x-xtream-plot'];
    final coverUrl = info?.info.coverUrl ?? channel.logo?.toString();

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

    // "3 temporadas" (§2.7, frame 44:2) — desde la CLAVE del mapa
    // `episodesBySeason`, no `info.seasons.length`: `XtreamSeriesInfo
    // .seasons` no es la fuente de verdad para la agrupación real (ver su
    // docstring, incoherencia real de fixture T1.1), así que tampoco lo es
    // para contarlas.
    final seasonCount = episodesBySeason.length;

    return Scaffold(
      body: SingleChildScrollView(
        child: DetailHero(
          title: title,
          backdropUrl: info?.info.backdropUrl,
          coverUrl: coverUrl,
          heroTag: widget.heroTag,
          content: Padding(
            padding: const EdgeInsets.symmetric(horizontal: IptvSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: textTheme.headlineMedium),
                if (year != null || seasonCount > 0 || genre != null || rating != null) ...[
                  const SizedBox(height: IptvSpacing.xs),
                  Text(
                    [
                      ?year,
                      if (seasonCount > 0) l10n.seriesDetailSeasonCount(seasonCount),
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
                    if (continueTarget != null)
                      FilledButton.icon(
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
                        icon: const Icon(Symbols.play_arrow_rounded),
                        label: Text(
                          l10n.seriesDetailContinueEpisode(continueTarget.season, continueTarget.episodeNumber),
                        ),
                      ),
                    const SizedBox(width: IptvSpacing.md),
                    // `44:2` no dibuja este botón, pero ui-spec §2.7 lo
                    // exige — misma decisión que el resto de controles que
                    // Figma fija como tratamiento visual, no como
                    // inventario cerrado (ver docstring de PlayerOverlay).
                    FavoriteBounceButton(
                      itemKey: Key('contentDetail.favorite.${channel.ref.serialized}'),
                      isFavorite: isFavorite,
                      tooltip: isFavorite ? l10n.favoriteRemoveTooltip : l10n.favoriteAddTooltip,
                      onPressed: () => ref.read(manageFavoritesProvider).toggle(channel.ref),
                    ),
                  ],
                ),
                if (seasons.length > 1) ...[
                  const SizedBox(height: IptvSpacing.lg),
                  Wrap(
                    key: const Key('seriesDetail.seasonSelector'),
                    spacing: IptvSpacing.sm,
                    children: [
                      for (final season in seasons)
                        _SeasonChip(
                          itemKey: Key('seriesDetail.season.$season'),
                          label: l10n.seriesDetailSeasonLabel(season),
                          selected: season == selectedSeason,
                          onTap: () => setState(() => _selectedSeason = season),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: IptvSpacing.md),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150), // 44:54
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeOut,
                  child: Column(
                    key: ValueKey(selectedSeason),
                    children: [
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
                ),
                const SizedBox(height: IptvSpacing.xl),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Mismo criterio tolerante que `VodDetailScreen._yearOf`.
  static String? _yearOf(String? raw) {
    if (raw == null || raw.length < 4) return null;
    final year = raw.substring(0, 4);
    return int.tryParse(year) != null ? year : null;
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

/// Pill de temporada (`44:11`/`44:12`) — fondo animado con
/// `AnimatedContainer` 150ms easeOut (nodo Figma `44:54`, "en paralelo"
/// con el cross-fade de la lista de episodios).
class _SeasonChip extends StatelessWidget {
  const _SeasonChip({
    required this.itemKey,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Key itemKey;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: itemKey,
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: IptvSpacing.md, vertical: IptvSpacing.xs),
        decoration: BoxDecoration(
          color: selected ? IptvColors.accent : IptvColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: selected ? null : Border.all(color: IptvColors.border),
        ),
        child: Text(
          label,
          style: IptvTypography.labelDesktop.copyWith(
            color: selected ? IptvColors.onyx.accentOn : IptvColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// Fila de episodio rediseñada (`44:19`): miniatura 96×54 alimentada por
/// [XtreamEpisode.stillUrl] — el objetivo declarado del paso 8, campo
/// existente desde el paso 2 sin consumidor hasta ahora — título, "42
/// min", barra de progreso y anillo+halo de foco (`IptvFocus`, ui-spec
/// §5.3: elementos interactivos elevados en Desktop, foco **y**
/// hover/pressed, mismo patrón que `MediaCard`; antes del rediseño esta
/// fila era un `InkWell` sin ningún tratamiento de foco).
class _EpisodeRow extends StatefulWidget {
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
  State<_EpisodeRow> createState() => _EpisodeRowState();
}

class _EpisodeRowState extends State<_EpisodeRow> {
  final FocusNode _focusNode = FocusNode();
  bool _focused = false;
  bool _hovering = false;
  bool _pressed = false;

  bool get _highlighted => _focused || _hovering || _pressed;

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
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final episode = widget.episode;
    final watchState = widget.watchState;
    final duration = episode.durationSecs != null ? Duration(seconds: episode.durationSecs!) : null;
    final fraction = watchState != null && !watchState.isFinished ? watchState.fraction : null;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: InkWell(
        key: Key('seriesDetail.episode.${widget.channel.ref.serialized}'),
        focusNode: _focusNode,
        onTap: widget.onTap,
        onHighlightChanged: (pressed) => setState(() => _pressed = pressed),
        borderRadius: BorderRadius.circular(IptvSpacing.radius),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: IptvSpacing.xs, horizontal: IptvSpacing.xs),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(IptvSpacing.radius),
            border: _highlighted ? IptvFocus.ring() : null,
            boxShadow: _highlighted ? IptvFocus.haloShadow() : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(width: 96, height: 54, child: _EpisodeThumbnail(episode: episode)),
              ),
              const SizedBox(width: IptvSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'E${episode.episodeNum} · ${episode.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleMedium?.copyWith(color: IptvColors.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    if (duration != null)
                      Text(
                        formatDurationHoursMinutes(l10n, duration),
                        style: textTheme.bodySmall?.copyWith(color: IptvColors.textSecondary),
                      ),
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
            ],
          ),
        ),
      ),
    );
  }
}

class _EpisodeThumbnail extends StatelessWidget {
  const _EpisodeThumbnail({required this.episode});

  final XtreamEpisode episode;

  @override
  Widget build(BuildContext context) {
    final url = episode.stillUrl;
    if (url == null) return _fallback(episode.title);
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      memCacheWidth: 192,
      placeholder: (_, _) => _fallback(episode.title),
      errorWidget: (_, _, _) => _fallback(episode.title),
    );
  }

  Widget _fallback(String label) => ColoredBox(
    color: IptvColors.surface,
    child: Center(
      child: Icon(
        Symbols.movie_rounded,
        size: IptvIconSizes.inline,
        color: IptvColors.textSecondary,
        semanticLabel: label,
      ),
    ),
  );
}
