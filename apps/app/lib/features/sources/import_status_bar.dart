import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iptv_tokens/iptv_tokens.dart';

import '../../l10n/app_localizations.dart';
import 'import_controller.dart';
import 'import_screen.dart';

/// Indicador global de import en segundo plano (ui-spec §2.14: "en segundo
/// plano, se puede navegar"). Vive en `DesktopShell` — el import sigue
/// corriendo (`importControllerProvider` no es `autoDispose`) aunque el
/// usuario esté en cualquier otra sección; este chip es la única señal de
/// que hay uno en curso, y al pulsarlo vuelve a la pantalla de progreso.
///
/// No pinta nada fuera de [ImportRunning] — los estados finales
/// (Done/Failed/Cancelled) solo importan mientras el usuario está mirando
/// la propia pantalla de importación, no como indicador persistente.
class ImportStatusBar extends ConsumerWidget {
  const ImportStatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(importControllerProvider);
    if (state is! ImportRunning) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);

    return Material(
      color: IptvColors.accent,
      child: InkWell(
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const ImportScreen())),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: IptvSpacing.md,
            vertical: IptvSpacing.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: IptvSpacing.sm),
              Text(
                l10n.importStatusBarRunning(state.sourceName),
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: IptvColors.textPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
