import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iptv_playback/iptv_playback.dart';
import 'package:iptv_tokens/iptv_tokens.dart';

import 'features/epg/epg_providers.dart';
import 'features/maintenance/maintenance_providers.dart';
import 'l10n/app_localizations.dart';
import 'providers/locale_override_provider.dart';
import 'shell/desktop_shell.dart';
import 'shell/form_factor.dart';
import 'shell/mobile_shell.dart';
import 'shell/tv_shell.dart';

void main() {
  initializePlayback();
  runApp(const ProviderScope(child: IptvApp()));
}

/// Arranque único de media_kit (S6, ADR-009) — antes de `runApp`, una sola
/// vez por proceso. `apps/app` nunca importa `media_kit` directamente (P6):
/// solo `iptv_playback`, que lo encapsula.
///
/// Extraído de `main()` (en vez de llamar a `IptvPlayback.ensureInitialized`
/// inline) para que el wiring sea verificable en test (política de
/// CLAUDE.md, commit `0ddc345`: un servicio arrancado sin verificar que
/// algo lo invoca de verdad es el mismo fallo que dejó `PurgeScheduler`
/// inerte en S2-S5) sin invocar el `MediaKit.ensureInitialized()` real —
/// exige libmpv nativo, ausente en el runner de CI (mismo límite que
/// `MediaKitPlayer`, ver su docstring). [ensureInitialized] es
/// [IptvPlayback.ensureInitialized] por defecto; `main_test.dart` lo
/// sustituye por un espía.
@visibleForTesting
void initializePlayback({void Function() ensureInitialized = IptvPlayback.ensureInitialized}) {
  ensureInitialized();
}

/// `ConsumerStatefulWidget` en vez de `StatelessWidget` (S5.5, Bloque B4)
/// para tener un `initState` donde arrancar los dos trabajos periódicos de
/// `core` mientras la app está abierta: la purga (`RunPurge`, S2 — escrita
/// desde entonces, nunca arrancada hasta ahora) y el refresco automático
/// de guía (`RunEpgRefresh`, S5.5). Ninguno de los dos necesita
/// infraestructura de background nueva (eso es F6) — ambos paran solos
/// cuando la app se cierra, vía `ref.onDispose` en sus providers.
class IptvApp extends ConsumerStatefulWidget {
  const IptvApp({super.key});

  @override
  ConsumerState<IptvApp> createState() => _IptvAppState();
}

class _IptvAppState extends ConsumerState<IptvApp> {
  @override
  void initState() {
    super.initState();
    unawaited(ref.read(purgeSchedulerProvider).start());
    unawaited(ref.read(epgRefreshSchedulerProvider).start());
  }

  @override
  Widget build(BuildContext context) {
    return IptvMaterialApp(
      home: switch (FormFactorDetector.detect()) {
        FormFactor.tv => const TvShell(),
        FormFactor.mobile => const MobileShell(),
        FormFactor.desktop => const DesktopShell(),
      },
    );
  }
}

/// Cableado común de `MaterialApp` (tema, título, i18n — D4). Separado de
/// [IptvApp] para poder testear la resolución de locale (en/es/fallback a
/// en, override manual) con un `home` trivial, sin depender de los shells
/// reales — ver `test/l10n_test.dart`.
class IptvMaterialApp extends ConsumerWidget {
  const IptvMaterialApp({required this.home, super.key});

  final Widget home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localeOverride = ref.watch(localeOverrideProvider);

    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: IptvTheme.dark(),
      // D4 requisito 5: override manual (null = sigue la locale del
      // sistema). D4 requisito 4: `supportedLocales` empieza por `en`, así
      // que la resolución por defecto de Flutter cae ahí cuando la locale
      // del sistema no es ni `en` ni `es` (verificado en test, no asumido).
      locale: localeOverride,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    );
  }
}
