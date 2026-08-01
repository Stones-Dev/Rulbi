import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/l10n/app_localizations.dart';
import 'package:iptv_app/main.dart';
import 'package:iptv_app/providers/locale_override_provider.dart';

/// D4 (idiomas v1: es + en, plan.md rev. 1.4). Escrito ANTES de cablear
/// `AppLocalizations` en `MaterialApp` (deben fallar en rojo hasta ese
/// cableado); verifica los 6 requisitos técnicos del "Hecho cuando" de la
/// tarea de Notion "i18n base (arb/l10n cableado)".
///
/// Usa `IptvMaterialApp` con un `home` trivial (no los shells reales) para
/// aislar la resolución de locale de la implementación de `DesktopShell`
/// (Ola 1, commit separado) — sigue siendo la misma configuración de
/// `MaterialApp` que corre en producción, solo con un `home` mínimo.
void main() {
  Widget homeReadingNavHome() =>
      Builder(builder: (context) => Text(AppLocalizations.of(context).navHome));

  testWidgets('con locale en, AppLocalizations devuelve la cadena base', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(child: IptvMaterialApp(home: homeReadingNavHome())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('con locale es, AppLocalizations devuelve la traducción', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = const [Locale('es')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    await tester.pumpWidget(
      ProviderScope(child: IptvMaterialApp(home: homeReadingNavHome())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Inicio'), findsOneWidget);
    expect(find.text('Home'), findsNothing);
  });

  testWidgets('con locale de sistema no soportada (fr), la app cae a inglés', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = const [Locale('fr')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    await tester.pumpWidget(
      ProviderScope(child: IptvMaterialApp(home: homeReadingNavHome())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Accueil'), findsNothing);
  });

  testWidgets(
    'channelCount pluraliza y lastUpdated formatea fecha distinto en en/es',
    (tester) async {
      final enLocalizations = await AppLocalizations.delegate.load(
        const Locale('en'),
      );
      final esLocalizations = await AppLocalizations.delegate.load(
        const Locale('es'),
      );
      final date = DateTime(2026, 8, 1);

      expect(enLocalizations.channelCount(0), 'No channels');
      expect(enLocalizations.channelCount(1), '1 channel');
      expect(enLocalizations.channelCount(3), '3 channels');
      expect(esLocalizations.channelCount(0), 'Sin canales');
      expect(esLocalizations.channelCount(1), '1 canal');
      expect(esLocalizations.channelCount(3), '3 canales');

      expect(
        enLocalizations.lastUpdated(date),
        isNot(esLocalizations.lastUpdated(date)),
      );
    },
  );

  testWidgets(
    'el override manual de locale fuerza es aunque el sistema esté en en',
    (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('en')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(localeOverrideProvider.notifier).state = const Locale(
        'es',
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: IptvMaterialApp(home: homeReadingNavHome()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Inicio'), findsOneWidget);
    },
  );
}
