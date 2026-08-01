import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iptv_tokens/iptv_tokens.dart';

import '../l10n/app_localizations.dart';

/// Shell de escritorio: `NavigationRail` lateral persistente + `IndexedStack`
/// con las 9 secciones de ui-spec.md §1 (Inicio · TV en directo · Películas
/// · Series · Buscar · Guía · Favoritos · Fuentes · Ajustes) + atajos de
/// teclado `Ctrl+1`…`Ctrl+9`. Todas las secciones son placeholder hoy — las
/// pantallas reales llegan en las Olas 2-3 de S4 y en sprints posteriores.
class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key});

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  int _selectedIndex = 0;
  final FocusNode _focusNode = FocusNode();

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
          body: Row(
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
                      padding: const EdgeInsets.symmetric(
                        vertical: IptvSpacing.md,
                      ),
                      child: Text(
                        l10n.appTitle,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(color: IptvColors.textPrimary),
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
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
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
                    for (final label in labels)
                      _SectionPlaceholder(label: label),
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
