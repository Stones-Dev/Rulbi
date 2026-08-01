import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iptv_tokens/iptv_tokens.dart';

import 'l10n/app_localizations.dart';
import 'providers/locale_override_provider.dart';
import 'shell/desktop_shell.dart';
import 'shell/form_factor.dart';
import 'shell/mobile_shell.dart';
import 'shell/tv_shell.dart';

void main() {
  runApp(const ProviderScope(child: IptvApp()));
}

class IptvApp extends StatelessWidget {
  const IptvApp({super.key});

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
