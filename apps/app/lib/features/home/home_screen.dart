import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iptv_tokens/iptv_tokens.dart';

import '../../l10n/app_localizations.dart';
import '../sources/source_providers.dart';
import 'continue_watching_row.dart';
import 'home_providers.dart';

/// Home desktop (ui-spec §2.2, S5 · Ola 1): esta ola solo entrega la fila
/// "Continuar viendo". Favoritos y "Ahora en tus canales" son Ola 2 —
/// hueco estructural deliberado en [_HomeContent], sin datos falsos ni
/// placeholder visible (ver handoff de cierre de esta ola).
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

class _HomeContent extends ConsumerWidget {
  const _HomeContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final continueWatchingAsync = ref.watch(continueWatchingProvider);

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
          // Favoritos y "Ahora en tus canales" (ui-spec §2.2) llegan en
          // S5 · Ola 2 — hueco estructural a propósito: nada se renderiza
          // aquí todavía, ni siquiera un título de sección, para no
          // sugerir una funcionalidad que aún no existe.
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
