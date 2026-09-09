import 'dart:async';

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
import '../features/settings/settings_screen.dart';
import '../features/sources/import_status_bar.dart';
import '../features/sources/sources_screen.dart';
import '../l10n/app_localizations.dart';
import 'tv_focusable.dart';

/// Shell de 10 pies para Android TV / Fire TV / webOS (S8 · TV base, ui-spec §1).
///
/// Características clave:
/// - Safe area de 88px horizontal (`IptvSpacing.safeAreaTv`) según ui-spec §5.2.
/// - Barra superior con logotipo "RULBI", destinos de navegación D-pad y reloj digital en tiempo real.
/// - Home 10-foot con las 3 filas canónicas (Continuar viendo, Favoritos, Ahora en tus canales)
///   o estado vacío accesible con control remoto vía [HomeScreen].
/// - Navegación entre secciones vía `IndexedStack` + captura del botón Atrás (Back)
///   para retornar a Inicio antes de salir.
/// - Operable al 100% con control remoto (flechas D-pad, OK/Center, Back).
class TvShell extends ConsumerStatefulWidget {
  const TvShell({super.key});

  @override
  ConsumerState<TvShell> createState() => _TvShellState();
}

class _TvShellState extends ConsumerState<TvShell> {
  int _selectedIndex = 0;

  static const _homeIndex = 0;
  static const _sourcesIndex = 7;

  void _selectIndex(int index) {
    if (index == _selectedIndex) return;
    setState(() => _selectedIndex = index);
  }

  bool _handleBackPress() {
    if (_selectedIndex != _homeIndex) {
      setState(() => _selectedIndex = _homeIndex);
      return false; // Interceptado: vuelve a Home
    }
    return true; // En Home: permite al sistema salir
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return PopScope(
      canPop: _selectedIndex == _homeIndex,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _handleBackPress();
        }
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              _handleBackPress(),
          const SingleActivator(LogicalKeyboardKey.goBack): () =>
              _handleBackPress(),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: IptvColors.background,
            body: Column(
            children: [
              // Barra de importación global en segundo plano
              const ImportStatusBar(),
              // Barra superior 10-foot (Logotipo, Navegación rápida y Reloj)
              _TvTopBar(
                selectedIndex: _selectedIndex,
                onDestinationSelected: _selectIndex,
              ),
              // Contenido principal por secciones
              Expanded(
                child: IndexedStack(
                  index: _selectedIndex,
                  children: [
                    HomeScreen(
                      contentPadding: IptvSpacing.safeAreaTv,
                      onGoToSources: () => _selectIndex(_sourcesIndex),
                    ),
                    const ChannelListScreen(),
                    const CatalogScreen(type: ContentType.vod),
                    const CatalogScreen(type: ContentType.series),
                    const SearchScreen(),
                    _TvSectionPlaceholder(label: l10n.navGuide),
                    const FavoritesScreen(),
                    const SourcesScreen(showSectionTitle: false),
                    const SettingsScreen(),
                  ],
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

/// Barra superior de navegación para TV (Figma Frame 41:2).
class _TvTopBar extends StatelessWidget {
  const _TvTopBar({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;

    final destinations = [
      (Icons.home_rounded, l10n.navHome),
      (Icons.live_tv_rounded, l10n.navLiveTv),
      (Icons.movie_rounded, l10n.navMovies),
      (Icons.video_library_rounded, l10n.navSeries),
      (Icons.search_rounded, l10n.navSearch),
      (Icons.grid_view_rounded, l10n.navGuide),
      (Icons.favorite_rounded, l10n.navFavorites),
      (Icons.source_rounded, l10n.navSources),
      (Icons.settings_rounded, l10n.navSettings),
    ];

    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(
        horizontal: IptvSpacing.safeAreaTv,
      ),
      child: Row(
        children: [
          // Logotipo "RULBI"
          Text(
            'RULBI',
            style: textTheme.headlineMedium?.copyWith(
              color: IptvColors.accent,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(width: IptvSpacing.xl),
          // Destinos de navegación con foco D-pad
          Expanded(
            child: SizedBox(
              height: 48,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var i = 0; i < destinations.length; i++) ...[
                      _TvNavPill(
                        icon: destinations[i].$1,
                        label: destinations[i].$2,
                        isSelected: selectedIndex == i,
                        onTap: () => onDestinationSelected(i),
                      ),
                      if (i < destinations.length - 1)
                        const SizedBox(width: IptvSpacing.sm),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: IptvSpacing.md),
          // Reloj digital en vivo
          const _TvClock(),
        ],
      ),
    );
  }
}

/// Botón / Pill de navegación superior para TV con foco visible.
class _TvNavPill extends StatelessWidget {
  const _TvNavPill({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return TvFocusable(
      onTap: onTap,
      borderRadius: IptvSpacing.radius,
      scale: 1.05,
      padding: const EdgeInsets.symmetric(
        horizontal: IptvSpacing.md,
        vertical: IptvSpacing.xs,
      ),
      child: Container(
        color: isSelected
            ? IptvColors.surface.withValues(alpha: 0.9)
            : Colors.transparent,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? IptvColors.accent : IptvColors.textSecondary,
            ),
            const SizedBox(width: IptvSpacing.xs),
            Text(
              label,
              style: textTheme.labelLarge?.copyWith(
                color: isSelected
                    ? IptvColors.textPrimary
                    : IptvColors.textSecondary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reloj digital para TV (actualizado automáticamente cada minuto).
class _TvClock extends StatefulWidget {
  const _TvClock();

  @override
  State<_TvClock> createState() => _TvClockState();
}

class _TvClockState extends State<_TvClock> {
  String _timeString = '';
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _updateTime());
  }

  void _updateTime() {
    final now = DateTime.now();
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    final newTime = '$hour:$minute';
    if (_timeString != newTime) {
      if (mounted) {
        setState(() => _timeString = newTime);
      } else {
        _timeString = newTime;
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _timeString,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
        color: IptvColors.textSecondary,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}

class _TvSectionPlaceholder extends StatelessWidget {
  const _TvSectionPlaceholder({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        label,
        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
          color: IptvColors.textSecondary,
        ),
      ),
    );
  }
}
