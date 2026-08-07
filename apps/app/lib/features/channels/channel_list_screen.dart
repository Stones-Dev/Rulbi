import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_tokens/iptv_tokens.dart';

import '../../l10n/app_localizations.dart';
import '../epg/epg_providers.dart';
import '../sources/import_controller.dart';
import '../sources/source_providers.dart';
import 'category_panel.dart';
import 'channel_page_cache.dart';
import 'channel_providers.dart';
import 'channel_row.dart';

/// Listado de canales (ui-spec §2.3, S5 · Ola 1) — sección "TV en directo"
/// del `DesktopShell`. Solo `ContentType.live`: Películas/Series no
/// tienen pantalla de navegación especificada en ui-spec (§2.6/§2.7 son
/// detalle con póster, no listado) — quedan como placeholder hasta que
/// esa spec exista, ver handoff de cierre de esta ola.
class ChannelListScreen extends ConsumerStatefulWidget {
  const ChannelListScreen({super.key});

  @override
  ConsumerState<ChannelListScreen> createState() => _ChannelListScreenState();
}

class _ChannelListScreenState extends ConsumerState<ChannelListScreen> {
  String? _selectedCategoryId;
  late ChannelPageCache _cache;

  /// Una instancia por pantalla (S5 · Ola 2), mismo criterio que `_cache`:
  /// no se reconstruye con `_rebuildCache` — un cambio de categoría no
  /// invalida la guía ya cargada de los canales que sigan visibles.
  late final EpgNowController _epgController;

  @override
  void initState() {
    super.initState();
    _cache = _createCache();
    _cache.init();
    _epgController = createEpgNowController(ref);
  }

  ChannelPageCache _createCache() {
    return ChannelPageCache(
      repository: ref.read(channelRepositoryProvider),
      query: ChannelQuery(
        type: ContentType.live,
        sourceIds: ref.read(activeSourceIdsProvider),
        categoryId: _selectedCategoryId,
      ),
    );
  }

  /// Reconstruye la caché de páginas — no hay forma de "refrescar en
  /// sitio" una ventana de páginas ya cargadas (S5 · Ola 1: se pierde el
  /// `.watch()` reactivo de drift, ver docstring de `ChannelPageCache`),
  /// así que cualquier cambio que invalide los datos crea una caché
  /// nueva y descarta la anterior.
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

  @override
  void dispose() {
    _cache.dispose();
    _epgController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // Reconstruye la caché cuando cambian las fuentes activas (toggle en
    // Gestión de fuentes) o termina un import — `ref.listen` corre tras
    // el build, así que `setState` dentro de `_rebuildCache` es seguro
    // aquí, a diferencia de si se llamara directamente desde `build`.
    ref.listen<Set<String>>(activeSourceIdsProvider, (previous, next) {
      if (previous != next) _rebuildCache();
    });
    ref.listen<Map<String, bool>>(lastImportStatusProvider, (_, _) {
      _rebuildCache();
    });

    final sourceIds = ref.watch(activeSourceIdsProvider);
    final categoryQuery = ChannelQuery(
      type: ContentType.live,
      sourceIds: sourceIds,
    );
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
            builder: (context, _) => _ChannelListBody(
              cache: _cache,
              l10n: l10n,
              epgController: _epgController,
            ),
          ),
        ),
      ],
    );
  }
}

class _ChannelListBody extends StatelessWidget {
  const _ChannelListBody({
    required this.cache,
    required this.l10n,
    required this.epgController,
  });

  final ChannelPageCache cache;
  final AppLocalizations l10n;
  final EpgNowController epgController;

  @override
  Widget build(BuildContext context) {
    if (!cache.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    if (cache.totalCount == 0) {
      return _EmptyChannelList(l10n: l10n);
    }
    return ListView.builder(
      key: const Key('channelListView'),
      itemExtent: channelRowExtent,
      itemCount: cache.totalCount,
      itemBuilder: (context, index) {
        final channel = cache.itemAt(index);
        return channel == null
            ? const ChannelRowSkeleton()
            : ChannelRow(channel: channel, epgController: epgController);
      },
    );
  }
}

class _EmptyChannelList extends StatelessWidget {
  const _EmptyChannelList({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.live_tv_outlined,
            size: 64,
            color: IptvColors.textSecondary,
          ),
          const SizedBox(height: IptvSpacing.md),
          Text(
            l10n.channelListEmptyTitle,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: IptvSpacing.sm),
          Text(l10n.channelListEmptyHint, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
