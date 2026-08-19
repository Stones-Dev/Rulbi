import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_tokens/iptv_tokens.dart';

import '../../l10n/app_localizations.dart';
import '../channels/category_panel.dart';
import '../channels/channel_page_cache.dart';
import '../channels/channel_providers.dart';
import '../sources/import_controller.dart';
import '../sources/source_providers.dart';
import 'poster_card.dart';
import 'series_detail_screen.dart';
import 'vod_detail_screen.dart';

/// Rejilla de Películas/Series (ui-spec §2.3.1, S5.5) — mismo patrón que
/// `ChannelListScreen` (categorías + `ChannelPageCache` + reconstrucción
/// ante cambios de fuentes/import), pero en rejilla de pósteres, no lista
/// de filas: el póster es el dato principal, no un logo pequeño (ver
/// `PosterCard`).
///
/// Una instancia por [type] (`ContentType.vod`/`ContentType.series`) —
/// ui-spec §2.3.1 pide "dos pestañas o selector Películas/Series", pero el
/// `NavigationRail` de `DesktopShell` ya las separa en dos destinos
/// distintos (índices 2 y 3): añadir pestañas dentro de cada destino
/// navegaría dos veces por lo mismo. Desviación declarada en el cierre de
/// S5.5, no decidida en silencio — ver plan de la ola.
class CatalogScreen extends ConsumerStatefulWidget {
  const CatalogScreen({super.key, required this.type});

  final ContentType type;

  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen> {
  String? _selectedCategoryId;
  late ChannelPageCache _cache;

  @override
  void initState() {
    super.initState();
    _cache = _createCache();
    _cache.init();
  }

  ChannelPageCache _createCache() {
    return ChannelPageCache(
      repository: ref.read(channelRepositoryProvider),
      query: ChannelQuery(
        type: widget.type,
        sourceIds: ref.read(activeSourceIdsProvider),
        categoryId: _selectedCategoryId,
      ),
    );
  }

  /// Mismo criterio que `ChannelListScreen._rebuildCache`: sin forma de
  /// "refrescar en sitio" una ventana de páginas ya cargadas, cualquier
  /// cambio que invalide los datos crea una caché nueva.
  void _rebuildCache() {
    final oldCache = _cache;
    final newCache = _createCache();
    newCache.init();
    setState(() => _cache = newCache);
    oldCache.dispose();
  }

  void _selectCategory(String? categoryId) {
    setState(() => _selectedCategoryId = categoryId);
    _rebuildCache();
  }

  /// Despacha por [Channel.type] (D6, S6): §2.6 Detalle VOD / §2.7 Detalle
  /// de serie son pantallas distintas — el selector de temporada y la
  /// lista de episodios no tienen equivalente en VOD.
  void _openDetail(Channel channel) {
    // Mismo string que la `Key` de `PosterCard` — `Hero` empareja tags
    // exactos entre origen y destino (S6.5 paso 7e).
    final heroTag = 'posterCard.${channel.ref.serialized}';
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => switch (channel.type) {
          ContentType.series => SeriesDetailScreen(channel: channel, heroTag: heroTag),
          ContentType.vod || ContentType.live => VodDetailScreen(channel: channel, heroTag: heroTag),
        },
      ),
    );
  }

  @override
  void dispose() {
    _cache.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // Mismo motivo que ChannelListScreen: ref.listen corre tras el build,
    // así que setState dentro de _rebuildCache es seguro aquí.
    ref.listen<Set<String>>(activeSourceIdsProvider, (previous, next) {
      if (previous != next) _rebuildCache();
    });
    ref.listen<Map<String, bool>>(lastImportStatusProvider, (_, _) {
      _rebuildCache();
    });

    final sourceIds = ref.watch(activeSourceIdsProvider);
    final categoryQuery = ChannelQuery(type: widget.type, sourceIds: sourceIds);
    final categoriesAsync = ref.watch(categoriesWithCountProvider(categoryQuery));
    final allCountAsync = ref.watch(totalChannelCountProvider(categoryQuery));

    return Row(
      children: [
        SizedBox(
          width: 240,
          child: categoriesAsync.when(
            data: (categories) => CategoryPanel(
              categories: categories,
              allCount: allCountAsync.valueOrNull ?? 0,
              selectedCategoryId: _selectedCategoryId,
              onSelected: _selectCategory,
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => Center(child: Text(l10n.probeErrorUnknown)),
          ),
        ),
        const VerticalDivider(width: 1, color: IptvColors.border),
        Expanded(
          child: ListenableBuilder(
            listenable: _cache,
            builder: (context, _) => _CatalogGrid(
              cache: _cache,
              type: widget.type,
              l10n: l10n,
              onOpenDetail: _openDetail,
            ),
          ),
        ),
      ],
    );
  }
}

class _CatalogGrid extends StatelessWidget {
  const _CatalogGrid({
    required this.cache,
    required this.type,
    required this.l10n,
    required this.onOpenDetail,
  });

  final ChannelPageCache cache;
  final ContentType type;
  final AppLocalizations l10n;
  final ValueChanged<Channel> onOpenDetail;

  @override
  Widget build(BuildContext context) {
    if (!cache.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    if (cache.totalCount == 0) {
      return _EmptyCatalog(type: type, l10n: l10n);
    }
    return GridView.builder(
      key: const Key('catalogGridView'),
      padding: const EdgeInsets.all(IptvSpacing.md),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        mainAxisSpacing: IptvSpacing.md,
        crossAxisSpacing: IptvSpacing.md,
        childAspectRatio: 0.6,
      ),
      itemCount: cache.totalCount,
      itemBuilder: (context, index) {
        final channel = cache.itemAt(index);
        return channel == null
            ? const _PosterSkeleton()
            : PosterCard(
                channel: channel,
                heroTag: 'posterCard.${channel.ref.serialized}',
                onTap: () => onOpenDetail(channel),
              );
      },
    );
  }
}

class _PosterSkeleton extends StatelessWidget {
  const _PosterSkeleton();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(IptvSpacing.radius),
      child: Container(color: IptvColors.surface),
    );
  }
}

class _EmptyCatalog extends StatelessWidget {
  const _EmptyCatalog({required this.type, required this.l10n});

  final ContentType type;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final (icon, title, hint) = switch (type) {
      ContentType.vod => (Icons.movie_outlined, l10n.catalogEmptyMoviesTitle, l10n.catalogEmptyMoviesHint),
      ContentType.series => (
        Icons.video_library_outlined,
        l10n.catalogEmptySeriesTitle,
        l10n.catalogEmptySeriesHint,
      ),
      ContentType.live => (Icons.live_tv_outlined, l10n.channelListEmptyTitle, l10n.channelListEmptyHint),
    };

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: IptvColors.textSecondary),
          const SizedBox(height: IptvSpacing.md),
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: IptvSpacing.sm),
          Text(hint, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
