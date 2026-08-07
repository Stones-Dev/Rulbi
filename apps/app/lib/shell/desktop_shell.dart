import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_tokens/iptv_tokens.dart';

import '../features/catalog/catalog_screen.dart';
import '../features/channels/channel_list_screen.dart';
import '../features/favorites/favorites_screen.dart';
import '../features/home/home_screen.dart';
import '../features/search/search_screen.dart';
import '../features/sources/import_status_bar.dart';
import '../features/sources/sources_screen.dart';
import '../l10n/app_localizations.dart';

/// Shell de escritorio: `NavigationRail` lateral persistente + `IndexedStack`
/// con las 9 secciones de ui-spec.md §1 (Inicio · TV en directo · Películas
/// · Series · Buscar · Guía · Favoritos · Fuentes · Ajustes) + atajos de
/// teclado `Ctrl+1`…`Ctrl+9` + [ImportStatusBar] (ui-spec §2.14, S4 · Ola
/// 3: indicador global de import en segundo plano, visible desde
/// cualquier sección).
///
/// S5 · Ola 1 cableó Inicio (`HomeScreen`, ui-spec §2.2), TV en directo
/// (`ChannelListScreen`, ui-spec §2.3) y Buscar (`SearchScreen`, ui-spec
/// §2.11). S5 · Ola 2 añade Favoritos (`FavoritesScreen`) y completa Inicio
/// con sus tres filas. S5.5 (Bloque D) añade Películas/Series
/// (`CatalogScreen`, ui-spec §2.3.1, rejilla de pósteres — el hueco de
/// spec de S5 ya se cerró). Guía/Ajustes llegan en sprints posteriores.
class DesktopShell extends ConsumerStatefulWidget {
  const DesktopShell({super.key});

  @override
  ConsumerState<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends ConsumerState<DesktopShell> {
  int _selectedIndex = 0;
  final FocusNode _focusNode = FocusNode();

  /// Posiciones en `_labels`/`_iconsByDestination` (ui-spec §1, orden:
  /// **Inicio**·**TV**·**Películas**·**Series**·**Buscar**·Guía·
  /// **Favoritos**·**Fuentes**·Ajustes). Guía/Ajustes siguen siendo
  /// placeholder (sprints posteriores).
  static const _homeIndex = 0;
  static const _liveTvIndex = 1;
  static const _moviesIndex = 2;
  static const _seriesIndex = 3;
  static const _searchIndex = 4;
  static const _favoritesIndex = 6;
  static const _sourcesIndex = 7;

  static const _iconsByDestination = [
    Icons.home_outlined,
    Icons.live_tv_outlined,
    Icons.movie_outlined,
    Icons.video_library_outlined,
    Icons.search_outlined,
    Icons.grid_view_outlined,
    Icons.favorite_border,
    Icons.source_outlined,
    Icons.settings_outlined,
  ];

  static const _selectedIconsByDestination = [
    Icons.home,
    Icons.live_tv,
    Icons.movie,
    Icons.video_library,
    Icons.search,
    Icons.grid_view,
    Icons.favorite,
    Icons.source,
    Icons.settings,
  ];

  List<String> _labels(AppLocalizations l10n) => [
    l10n.navHome,
    l10n.navLiveTv,
    l10n.navMovies,
    l10n.navSeries,
    l10n.navSearch,
    l10n.navGuide,
    l10n.navFavorites,
    l10n.navSources,
    l10n.navSettings,
  ];

  void _selectIndex(int index) {
    if (index == _selectedIndex) return;
    setState(() => _selectedIndex = index);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final labels = _labels(l10n);

    return CallbackShortcuts(
      bindings: {
        for (var i = 0; i < labels.length; i++)
          SingleActivator(
            LogicalKeyboardKey(0x31 + i), // '1'..'9'
            control: true,
          ): () =>
              _selectIndex(i),
      },
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        child: Scaffold(
          backgroundColor: IptvColors.background,
          body: Column(
            children: [
              const ImportStatusBar(),
              Expanded(child: _buildBody(context, labels)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, List<String> labels) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final extended = MediaQuery.sizeOf(context).width >= 1000;
            final rail = NavigationRail(
              backgroundColor: IptvColors.surface,
              selectedIndex: _selectedIndex,
              onDestinationSelected: _selectIndex,
              extended: extended,
              labelType: extended
                  ? NavigationRailLabelType.none
                  : NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: IptvSpacing.md),
                child: Text(
                  l10n.appTitle,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: IptvColors.textPrimary,
                  ),
                ),
              ),
              destinations: [
                for (var i = 0; i < labels.length; i++)
                  NavigationRailDestination(
                    icon: Icon(_iconsByDestination[i]),
                    selectedIcon: Icon(_selectedIconsByDestination[i]),
                    label: Text(labels[i]),
                  ),
              ],
            );
            // Con 9 destinos + labelType.all (ventanas < 1000px), la
            // altura intrínseca del rail puede superar la disponible
            // (ventanas de escritorio bajas/TV). Patrón oficial de
            // Flutter para NavigationRail con muchos destinos:
            // envolverlo en scroll en vez de recortar destinos.
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(child: rail),
              ),
            );
          },
        ),
        const VerticalDivider(width: 1, color: IptvColors.border),
        Expanded(
          child: IndexedStack(
            index: _selectedIndex,
            children: [
              for (var i = 0; i < labels.length; i++)
                switch (i) {
                  _homeIndex => HomeScreen(
                    onGoToSources: () => _selectIndex(_sourcesIndex),
                  ),
                  _liveTvIndex => const ChannelListScreen(),
                  _moviesIndex => const CatalogScreen(type: ContentType.vod),
                  _seriesIndex => const CatalogScreen(type: ContentType.series),
                  _searchIndex => const SearchScreen(),
                  _favoritesIndex => const FavoritesScreen(),
                  _sourcesIndex => const SourcesScreen(),
                  _ => _SectionPlaceholder(label: labels[i]),
                },
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionPlaceholder extends StatelessWidget {
  const _SectionPlaceholder({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.headlineMedium?.copyWith(color: IptvColors.textPrimary),
      ),
    );
  }
}
