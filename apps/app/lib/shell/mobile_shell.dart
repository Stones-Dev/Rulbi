import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_tokens/iptv_tokens.dart';

import '../features/catalog/catalog_screen.dart';
import '../features/channels/channel_list_screen.dart';
import '../features/home/home_screen.dart';
import '../features/search/search_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/sources/import_status_bar.dart';
import '../features/sources/sources_screen.dart';
import '../l10n/app_localizations.dart';

/// Shell táctil (S7 · Móvil base, paso 1): `NavigationBar` inferior de
/// **5 destinos exactos** (ui-spec §1: Inicio · TV en directo · Cine ·
/// Series · Buscar) + `IndexedStack`, mismo patrón que `DesktopShell`
/// (`shell/desktop_shell.dart`) — no hay router en la app, y no se
/// introduce uno solo para este shell (sería un cambio transversal fuera
/// del alcance del sprint, ver ui-spec §1 "resto por pila").
///
/// El resto de secciones de Desktop (Guía · Favoritos · Fuentes ·
/// Ajustes) no caben en una barra de 5 destinos — van "por pila" detrás
/// del icono de Ajustes del `AppBar`, que abre [SettingsScreen]. Fuentes
/// tiene que quedar alcanzable (el DoD del sprint exige "con fuentes
/// funcionando"), así que la CTA del Home vacío (`onGoToSources`) también
/// empuja directo a [SourcesScreen] sin pasar por Ajustes.
///
/// Esqueleto del Sprint 0 (placeholder `Text('MobileShell')`) sustituido
/// por completo en S7.
class MobileShell extends ConsumerStatefulWidget {
  const MobileShell({super.key});

  @override
  ConsumerState<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends ConsumerState<MobileShell> {
  int _selectedIndex = 0;

  // Mismos glifos que los 5 primeros destinos del rail de Desktop
  // (desktop_shell.dart `_symbolsByDestination`) — coherencia de
  // iconografía entre shells (ui-spec §5.4).
  static const _symbolsByDestination = [
    Symbols.home_rounded,
    Symbols.live_tv_rounded,
    Symbols.movie_rounded,
    Symbols.video_library_rounded,
    Symbols.search_rounded,
  ];

  // Tamaño de botón de acción (ui-spec §5.4), no el 32 D-pad-safe de TV que
  // usa el rail de Desktop — ese valor es específico del frame de TV/Desktop
  // medido en Figma, no un token universal.
  static const double _iconSize = IptvIconSizes.action;

  Widget _symbolIcon(int index, {required bool selected}) => Icon(
    _symbolsByDestination[index],
    size: _iconSize,
    // Mismo patrón peso/relleno que el rail de Desktop para el estado activo.
    weight: selected ? 600 : 400,
    fill: selected ? 1 : 0,
  );

  List<String> _labels(AppLocalizations l10n) => [
    l10n.navHome,
    l10n.navLiveTv,
    l10n.navMovies,
    l10n.navSeries,
    l10n.navSearch,
  ];

  void _selectIndex(int index) {
    if (index == _selectedIndex) return;
    setState(() => _selectedIndex = index);
  }

  void _openSources() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SourcesScreen()));
  }

  void _openSettings() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final labels = _labels(l10n);

    return Scaffold(
      backgroundColor: IptvColors.background,
      appBar: AppBar(
        backgroundColor: IptvColors.surface,
        title: Text(l10n.appTitle),
        actions: [
          IconButton(
            icon: const Icon(Symbols.settings_rounded, size: _iconSize),
            tooltip: l10n.navSettings,
            onPressed: _openSettings,
          ),
        ],
      ),
      body: Column(
        children: [
          const ImportStatusBar(),
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: [
                HomeScreen(onGoToSources: _openSources),
                const ChannelListScreen(),
                const CatalogScreen(type: ContentType.vod),
                const CatalogScreen(type: ContentType.series),
                const SearchScreen(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: IptvColors.surface,
        selectedIndex: _selectedIndex,
        onDestinationSelected: _selectIndex,
        destinations: [
          for (var i = 0; i < labels.length; i++)
            NavigationDestination(
              icon: _symbolIcon(i, selected: false),
              selectedIcon: _symbolIcon(i, selected: true),
              label: labels[i],
            ),
        ],
      ),
    );
  }
}
