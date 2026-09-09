import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/features/sources/source_providers.dart';
import 'package:iptv_app/l10n/app_localizations.dart';
import 'package:iptv_app/shell/tv_shell.dart';

import '_helpers/fake_epg_repository.dart';
import '_helpers/fake_favorites_repository.dart';
import 'features/channels/_helpers/fake_channel_repository.dart';
import 'features/home/_helpers/fake_watch_state_repository.dart';
import 'features/sources/_helpers/fakes.dart';

/// TvShell navegable (S8 · TV base). Mismo patrón de fakes que
/// `desktop_shell_test.dart` y `mobile_shell_test.dart`: `IndexedStack`
/// construye todas las secciones a la vez, por lo que se inyectan los repos
/// falsos para evitar disparar la base de datos real.
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

  void configureTvScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Finder topBarLabel(String label) => find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.text(label),
      );

  testWidgets('renderiza con el logo RULBI y los 9 destinos en la barra superior', (
    tester,
  ) async {
    configureTvScreen(tester);
    await tester.pumpWidget(wrap(const TvShell()));
    await tester.pumpAndSettle();

    expect(find.text('RULBI'), findsOneWidget);

    for (final label in const [
      'Home',
      'Live TV',
      'Movies',
      'Series',
      'Search',
      'Guide',
      'Favorites',
      'Sources',
      'Settings',
    ]) {
      expect(topBarLabel(label), findsOneWidget);
    }
  });

  testWidgets('seleccionar un destino en la barra cambia la sección activa', (
    tester,
  ) async {
    configureTvScreen(tester);
    await tester.pumpWidget(wrap(const TvShell()));
    await tester.pumpAndSettle();

    final stackBefore = tester.widget<IndexedStack>(find.byType(IndexedStack));
    expect(stackBefore.index, 0);

    // Seleccionamos Search
    await tester.tap(topBarLabel('Search'));
    await tester.pumpAndSettle();

    final stackAfter = tester.widget<IndexedStack>(find.byType(IndexedStack));
    expect(stackAfter.index, 4);
  });

  testWidgets('pulsar Escape / Back retorna a Inicio desde una sección secundaria', (
    tester,
  ) async {
    configureTvScreen(tester);
    await tester.pumpWidget(wrap(const TvShell()));
    await tester.pumpAndSettle();

    // Navegar a Movies (índice 2)
    await tester.tap(topBarLabel('Movies'));
    await tester.pumpAndSettle();

    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 2);

    // Pulsamos tecla Escape (equivalente a Back del control remoto en escritorio/emulador)
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 0);
  });

  testWidgets('todas las etiquetas vienen de AppLocalizations (es vs en)', (
    tester,
  ) async {
    configureTvScreen(tester);
    await tester.pumpWidget(
      wrap(const TvShell(), locale: const Locale('es')),
    );
    await tester.pumpAndSettle();

    for (final label in const [
      'Inicio',
      'TV en directo',
      'Películas',
      'Series',
      'Buscar',
      'Guía',
      'Favoritos',
      'Fuentes',
      'Ajustes',
    ]) {
      expect(topBarLabel(label), findsOneWidget);
    }
  });

  testWidgets('biblioteca vacía en TV muestra CTA y cambia a Fuentes', (
    tester,
  ) async {
    configureTvScreen(tester);
    await tester.pumpWidget(wrap(const TvShell()));
    await tester.pumpAndSettle();

    // Con FakeSourceRepository vacío, HomeScreen muestra la vista vacía
    expect(find.byIcon(Icons.video_library_outlined), findsOneWidget);

    // Pulsamos el botón "Go to Sources" / "Add source" (Key: 'homeGoToSourcesButton')
    final ctaFinder = find.byKey(const Key('homeGoToSourcesButton'));
    expect(ctaFinder, findsOneWidget);

    await tester.tap(ctaFinder);
    await tester.pumpAndSettle();

    // Al pulsar la CTA debe navegar a la sección de Fuentes (índice 7)
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 7);
  });
}
