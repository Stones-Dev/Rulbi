import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_tokens/iptv_tokens.dart';

import '../../l10n/app_localizations.dart';
import '../channels/channel_row.dart';
import '../player/open_channel.dart';
import '../player/playback_request.dart';
import 'search_controller.dart';

/// Búsqueda global (ui-spec §2.11, S5 · Ola 1): campo de texto + grupos
/// Canales/Películas/Series. El estado vacío/sin-resultados no está en
/// ui-spec — fallback mínimo, ver handoff de cierre de esta ola.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _textController = TextEditingController();

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(searchControllerProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('searchField'),
            controller: _textController,
            autofocus: true,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: l10n.searchFieldHint,
            ),
            onChanged: (value) =>
                ref.read(searchControllerProvider.notifier).queryChanged(value),
          ),
          const SizedBox(height: IptvSpacing.md),
          Expanded(child: _SearchBody(state: state, l10n: l10n)),
        ],
      ),
    );
  }
}

class _SearchBody extends StatelessWidget {
  const _SearchBody({required this.state, required this.l10n});

  final SearchState state;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      SearchIdle() => const SizedBox.shrink(),
      SearchLoading() => const Center(child: CircularProgressIndicator()),
      SearchResults(:final query, :final results) when results.isEmpty =>
        Center(child: Text(l10n.searchNoResults(query))),
      SearchResults(:final query, :final results) => _SearchResultsList(
        query: query,
        results: results,
      ),
    };
  }
}

class _SearchResultsList extends ConsumerWidget {
  const _SearchResultsList({required this.query, required this.results});

  final String query;
  final GroupedSearchResults results;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return ListView(
      children: [
        if (results.live.isNotEmpty) ...[
          _SearchGroupHeader(title: l10n.searchGroupChannels),
          for (var i = 0; i < results.live.length; i++)
            ChannelRow(
              channel: results.live[i],
              highlightQuery: query,
              // S6, Bloque E: zapping ↑/↓ dentro de este mismo grupo de
              // resultados (ui-spec §2.11 → §2.13, D3 del plan de la ola).
              onTap: () => openChannel(
                context,
                ref,
                results.live[i],
                queue: PlaybackQueue(items: results.live, index: i),
              ),
            ),
        ],
        if (results.vod.isNotEmpty) ...[
          _SearchGroupHeader(title: l10n.searchGroupMovies),
          for (final channel in results.vod)
            ChannelRow(
              channel: channel,
              highlightQuery: query,
              // Abre la ficha VOD (§2.6) — sin cola: no es un contexto de
              // reproducción secuencial.
              onTap: () => openChannel(context, ref, channel),
            ),
        ],
        if (results.series.isNotEmpty) ...[
          _SearchGroupHeader(title: l10n.searchGroupSeries),
          for (final channel in results.series)
            ChannelRow(
              channel: channel,
              highlightQuery: query,
              onTap: () => openChannel(context, ref, channel),
            ),
        ],
      ],
    );
  }
}

class _SearchGroupHeader extends StatelessWidget {
  const _SearchGroupHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: IptvSpacing.sm),
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(color: IptvColors.textSecondary),
      ),
    );
  }
}
