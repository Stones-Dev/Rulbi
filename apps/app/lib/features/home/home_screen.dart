import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iptv_tokens/iptv_tokens.dart';

import '../../l10n/app_localizations.dart';
import '../epg/epg_providers.dart';
import '../favorites/favorites_providers.dart';
import '../sources/source_providers.dart';
import 'continue_watching_row.dart';
import 'favorites_row.dart';
import 'home_providers.dart';
import 'now_on_your_channels_row.dart';

/// Home desktop (ui-spec §2.2): las tres filas —"Continuar viendo"
/// (S5 · Ola 1), "Favoritos" y "Ahora en tus canales" (S5 · Ola 2)— juntas
/// cierran la tarea "Home desktop" (su criterio original exigía las tres).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({required this.onGoToSources, super.key});

  /// Cambia la sección del `DesktopShell` a Fuentes — la CTA del estado
  /// vacío (§2.2: "vacío → CTA a Fuentes"). No hay router en la app
  /// (`IndexedStack` del shell), así que quien construye `HomeScreen` es
  /// quien conoce cómo cambiar de sección.
  final VoidCallback onGoToSources;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final sourcesAsync = ref.watch(sourcesStreamProvider);

    return sourcesAsync.when(
      data: (sources) => sources.isEmpty
          ? _EmptyLibrary(onGoToSources: onGoToSources)
          : const _HomeContent(),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => Center(child: Text(l10n.probeErrorUnknown)),
    );
  }
}

class _HomeContent extends ConsumerStatefulWidget {
  const _HomeContent();

  @override
  ConsumerState<_HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends ConsumerState<_HomeContent> {
  /// Una instancia por pantalla (S5 · Ola 2), mismo criterio que
  /// `ChannelListScreen`/`FavoritesScreen` — solo la usa la fila "Ahora en
  /// tus canales"; "Continuar viendo"/"Favoritos" no muestran EPG.
  late final EpgNowController _epgController;

  @override
  void initState() {
    super.initState();
    _epgController = createEpgNowController(ref);
  }

  @override
  void dispose() {
    _epgController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final continueWatchingAsync = ref.watch(continueWatchingProvider);
    final favoritesAsync = ref.watch(favoritesListProvider);
    final nowOnYourChannelsAsync = ref.watch(nowOnYourChannelsProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: ListView(
        children: [
          continueWatchingAsync.when(
            data: (items) => items.isEmpty
                ? const SizedBox.shrink()
                : ContinueWatchingRow(items: items),
            loading: () => const SizedBox(
              height: 48,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => const SizedBox.shrink(),
          ),
          favoritesAsync.when(
            data: (channels) => channels.isEmpty
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: IptvSpacing.lg),
                    child: FavoritesRow(channels: channels),
                  ),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
          nowOnYourChannelsAsync.when(
            data: (channels) => channels.isEmpty
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: IptvSpacing.lg),
                    child: NowOnYourChannelsRow(
                      channels: channels,
                      epgController: _epgController,
                    ),
                  ),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.onGoToSources});

  final VoidCallback onGoToSources;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.video_library_outlined,
            size: 64,
            color: IptvColors.textSecondary,
          ),
          const SizedBox(height: IptvSpacing.md),
          Text(
            l10n.homeEmptyLibraryTitle,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: IptvSpacing.sm),
          Text(l10n.homeEmptyLibraryHint, textAlign: TextAlign.center),
          const SizedBox(height: IptvSpacing.md * 1.5),
          FilledButton(
            key: const Key('homeGoToSourcesButton'),
            onPressed: onGoToSources,
            child: Text(l10n.homeGoToSourcesButton),
          ),
        ],
      ),
    );
  }
}
