import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/features/sources/source_providers.dart';
import 'package:iptv_app/l10n/app_localizations.dart';
import 'package:iptv_app/shell/mobile_shell.dart';

import '_helpers/fake_epg_repository.dart';
import '_helpers/fake_favorites_repository.dart';
import 'features/channels/_helpers/fake_channel_repository.dart';
import 'features/home/_helpers/fake_watch_state_repository.dart';
import 'features/sources/_helpers/fakes.dart';

/// MobileShell navegable (S7 · Móvil base, paso 1). Mismo patrón de fakes
/// que `desktop_shell_test.dart`: `IndexedStack` construye las 5 secciones a
/// la vez, así que sin estos overrides cualquier test dispara
/// `iptvDatabaseProvider` real y `pumpAndSettle()` no termina.
void main() {
  Widget wrap(Widget child, {Locale locale = const Locale('en')}) {
    return ProviderScope(
      overrides: [
        sourceRepositoryProvider.overrideWithValue(FakeSourceRepository()),
        channelRepositoryProvider.overrideWithValue(
          FakeChannelListRepository(),
        ),
        watchStateRepositoryProvider.overrideWithValue(
          FakeWatchStateRepository(),
        ),
        favoritesRepositoryProvider.overrideWithValue(
          FakeFavoritesRepository(),
        ),
        epgRepositoryProvider.overrideWithValue(FakeEpgRepository()),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    );
  }

  // Los finders de etiqueta se acotan a la NavigationBar por el mismo motivo
  // que desktop_shell_test.dart: la sección activa puede repetir el texto.
  Finder navBarLabel(String label) => find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  );

  testWidgets('renderiza con los 5 destinos exactos de ui-spec §1 en la barra inferior', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const MobileShell()));
    await tester.pumpAndSettle();

    for (final label in const [
      'Home',
      'Live TV',
      'Movies',
      'Series',
      'Search',
    ]) {
      expect(navBarLabel(label), findsOneWidget);
    }
    // Nada de Guide/Favorites/Sources/Settings en la barra — ui-spec §1 fija
    // exactamente 5 destinos para móvil, el resto va "por pila".
    for (final label in const ['Guide', 'Favorites', 'Sources', 'Settings']) {
      expect(navBarLabel(label), findsNothing);
    }
  });

  testWidgets('tocar un destino cambia la sección activa del IndexedStack', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const MobileShell()));
    await tester.pumpAndSettle();

    final stackBefore = tester.widget<IndexedStack>(find.byType(IndexedStack));
    expect(stackBefore.index, 0);

    await tester.tap(navBarLabel('Search'));
    await tester.pumpAndSettle();

    final stackAfter = tester.widget<IndexedStack>(find.byType(IndexedStack));
    expect(stackAfter.index, isNot(0));
  });

  testWidgets('todas las etiquetas vienen de AppLocalizations (es vs en)', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(const MobileShell(), locale: const Locale('es')),
    );
    await tester.pumpAndSettle();

    for (final label in const [
      'Inicio',
      'TV en directo',
      'Películas',
      'Series',
      'Buscar',
    ]) {
      expect(navBarLabel(label), findsOneWidget);
    }
    expect(navBarLabel('Home'), findsNothing);
  });

  testWidgets(
    'el icono de Ajustes del AppBar abre SettingsScreen con Fuentes/Favoritos/Dispositivos',
    (tester) async {
      await tester.pumpWidget(wrap(const MobileShell()));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Sources'), findsOneWidget);
      expect(find.text('Favorites'), findsOneWidget);
      expect(find.text('Devices'), findsOneWidget);
    },
  );

  // Regresión de la verificación E2E de S7 (Antigravity, emulador Android):
  // este test previo nunca pulsaba el tile — solo comprobaba que el texto
  // aparecía — así que el "No Material widget found" al empujar
  // SourcesScreen sin Scaffold quedaba sin ejercer. Cubre los dos puntos de
  // entrada de mobile_shell.dart: el tile de Ajustes y la CTA del Home
  // vacío (`onGoToSources`), que empuja SourcesScreen directa sin pasar por
  // Ajustes.
  testWidgets(
    'pulsar el tile de Fuentes en Ajustes navega sin excepciones',
    (tester) async {
      await tester.pumpWidget(wrap(const MobileShell()));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sources'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(BackButton), findsOneWidget);
    },
  );

  testWidgets(
    'la CTA "Go to Sources" del Home vacío navega sin excepciones',
    (tester) async {
      await tester.pumpWidget(wrap(const MobileShell()));
      await tester.pumpAndSettle();

      // FakeSourceRepository empieza vacío (sin upsert) -> Home muestra
      // _EmptyLibrary con la CTA.
      await tester.tap(find.text('Go to Sources'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(BackButton), findsOneWidget);
    },
  );
}
