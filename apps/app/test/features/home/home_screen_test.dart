import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/features/home/home_screen.dart';
import 'package:iptv_app/features/player/player_screen.dart';
import 'package:iptv_app/features/sources/source_providers.dart';
import 'package:iptv_app/l10n/app_localizations.dart';
import 'package:iptv_core/iptv_core.dart';

import '../../_helpers/fake_epg_repository.dart';
import '../../_helpers/fake_favorites_repository.dart';
import '../channels/_helpers/fake_channel_repository.dart';
import '../sources/_helpers/fakes.dart';
import '_helpers/fake_watch_state_repository.dart';

/// Home desktop (ui-spec §2.2): las tres filas —"Continuar viendo"
/// (S5 · Ola 1), "Favoritos" y "Ahora en tus canales" (S5 · Ola 2).
void main() {
  Source activeSource({String id = 's1'}) => Source(
    id: id,
    config: M3uUrlSourceConfig(url: Uri.parse('http://example.com/$id.m3u')),
    name: 'Fuente $id',
    updatedAt: DateTime.utc(2026, 1, 1),
  );

  Channel channelOf(
    String sourceId,
    String key,
    String name, {
    ContentType type = ContentType.vod,
  }) => Channel(
    ref: ChannelRef(sourceId: sourceId, key: key),
    sourceId: sourceId,
    type: type,
    name: name,
    url: Uri.parse('http://example.com/$sourceId/$key'),
  );

  Future<void> pumpScreen(
    WidgetTester tester, {
    required FakeSourceRepository sources,
    required FakeChannelListRepository channels,
    required FakeWatchStateRepository watchState,
    VoidCallback? onGoToSources,
    List<NavigatorObserver> navigatorObservers = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sourceRepositoryProvider.overrideWithValue(sources),
          channelRepositoryProvider.overrideWithValue(channels),
          watchStateRepositoryProvider.overrideWithValue(watchState),
          favoritesRepositoryProvider.overrideWithValue(
            FakeFavoritesRepository(),
          ),
          epgRepositoryProvider.overrideWithValue(FakeEpgRepository()),
        ],
        child: MaterialApp(
          navigatorObservers: navigatorObservers,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: HomeScreen(onGoToSources: onGoToSources ?? () {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('sin fuentes, muestra el estado vacío con CTA a Fuentes', (
    tester,
  ) async {
    var tapped = false;
    await pumpScreen(
      tester,
      sources: FakeSourceRepository(),
      channels: FakeChannelListRepository(),
      watchState: FakeWatchStateRepository(),
      onGoToSources: () => tapped = true,
    );

    expect(find.text('Your library is empty'), findsOneWidget);

    await tester.tap(find.byKey(const Key('homeGoToSourcesButton')));
    expect(tapped, isTrue);
  });

  testWidgets(
    'con fuentes pero sin historial, no muestra la fila (sin datos falsos)',
    (tester) async {
      final sources = FakeSourceRepository();
      await sources.upsert(activeSource());

      await pumpScreen(
        tester,
        sources: sources,
        channels: FakeChannelListRepository(),
        watchState: FakeWatchStateRepository(),
      );

      expect(find.text('Your library is empty'), findsNothing);
      expect(find.text('Continue watching'), findsNothing);
    },
  );

  testWidgets(
    'con historial real, muestra la fila con nombre, progreso y tiempo restante',
    (tester) async {
      final sources = FakeSourceRepository();
      await sources.upsert(activeSource());

      final channel = channelOf('s1', 'oppenheimer', 'Oppenheimer');
      final channels = FakeChannelListRepository(channels: [channel]);

      final watchState = FakeWatchStateRepository()
        ..seed(
          WatchState(
            channel: channel.ref,
            position: const Duration(minutes: 30),
            duration: const Duration(hours: 2),
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        );

      await pumpScreen(
        tester,
        sources: sources,
        channels: channels,
        watchState: watchState,
      );

      expect(find.text('Continue watching'), findsOneWidget);
      expect(find.text('Oppenheimer'), findsOneWidget);
      // 90 min quedan de 120 -> 1h 30m.
      expect(find.text('1h 30m left'), findsOneWidget);
    },
  );

  testWidgets('un ítem en directo (duration cero) no muestra tiempo restante', (
    tester,
  ) async {
    final sources = FakeSourceRepository();
    await sources.upsert(activeSource());

    final channel = channelOf('s1', 'dazn1', 'DAZN 1', type: ContentType.live);
    final channels = FakeChannelListRepository(channels: [channel]);

    final watchState = FakeWatchStateRepository()
      ..seed(
        WatchState(
          channel: channel.ref,
          position: const Duration(minutes: 10),
          duration: Duration.zero,
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );

    await pumpScreen(
      tester,
      sources: sources,
      channels: channels,
      watchState: watchState,
    );

    // "DAZN 1" aparece dos veces desde S5 · Ola 2: en "Continuar viendo" y
    // también en "Ahora en tus canales" (es un canal en directo real de
    // esta misma fuente) — se acota a la tarjeta de "Continuar viendo"
    // (`ContinueWatchingRow`, clave `continueWatching.<ref>`) para seguir
    // comprobando específicamente esa fila.
    expect(
      find.descendant(
        of: find.byKey(Key('continueWatching.${channel.ref.serialized}')),
        matching: find.text('DAZN 1'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('left'), findsNothing);
  });

  testWidgets(
    'tocar Continuar viendo en un directo abre el reproductor SIN startAt (S6: seek sin sentido sobre live)',
    (tester) async {
      final sources = FakeSourceRepository();
      await sources.upsert(activeSource());

      final channel = channelOf('s1', 'dazn1', 'DAZN 1', type: ContentType.live);
      final channels = FakeChannelListRepository(channels: [channel]);
      final watchState = FakeWatchStateRepository()
        ..seed(
          WatchState(
            channel: channel.ref,
            position: const Duration(minutes: 10),
            duration: Duration.zero,
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        );

      final observer = _RecordingNavigatorObserver();
      await pumpScreen(
        tester,
        sources: sources,
        channels: channels,
        watchState: watchState,
        navigatorObservers: [observer],
      );

      await tester.tap(find.byKey(Key('continueWatching.${channel.ref.serialized}')));

      final route = observer.lastPushed;
      expect(route, isA<MaterialPageRoute<void>>());
      final widget = (route! as MaterialPageRoute<void>).builder(
        tester.element(find.byType(HomeScreen)),
      );
      expect(widget, isA<PlayerScreen>());
      expect((widget as PlayerScreen).request.startAt, Duration.zero);
    },
  );

  testWidgets(
    'tocar Continuar viendo en un VOD abre el reproductor con startAt = posición guardada',
    (tester) async {
      final sources = FakeSourceRepository();
      await sources.upsert(activeSource());

      final channel = channelOf('s1', 'oppenheimer', 'Oppenheimer');
      final channels = FakeChannelListRepository(channels: [channel]);
      const savedPosition = Duration(minutes: 30);
      final watchState = FakeWatchStateRepository()
        ..seed(
          WatchState(
            channel: channel.ref,
            position: savedPosition,
            duration: const Duration(hours: 2),
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        );

      final observer = _RecordingNavigatorObserver();
      await pumpScreen(
        tester,
        sources: sources,
        channels: channels,
        watchState: watchState,
        navigatorObservers: [observer],
      );

      await tester.tap(find.byKey(Key('continueWatching.${channel.ref.serialized}')));

      final route = observer.lastPushed;
      final widget = (route! as MaterialPageRoute<void>).builder(
        tester.element(find.byType(HomeScreen)),
      );
      expect((widget as PlayerScreen).request.startAt, savedPosition);
    },
  );

  testWidgets(
    'pull-to-refresh invalida las tres filas y vuelve a leer de los repositorios (S7 · Móvil base)',
    (tester) async {
      final sources = FakeSourceRepository();
      await sources.upsert(activeSource());

      final channel = channelOf(
        's1',
        'dazn1',
        'DAZN 1',
        type: ContentType.live,
      );
      final channels = FakeChannelListRepository(channels: [channel]);

      await pumpScreen(
        tester,
        sources: sources,
        channels: channels,
        watchState: FakeWatchStateRepository(),
      );

      // Único consumidor de `channelsPage` dentro de Home ("Ahora en tus
      // canales") — su crecimiento tras el refresh prueba que el provider
      // se invalidó y volvió a pedir datos de verdad, no solo que el
      // widget no lanzó una excepción.
      final requestsBefore = channels.pageRequests.length;

      // `show()` no se puede `await` directamente: su animación depende de
      // un `Ticker` real que solo avanza con `pump()` — awaitarla sin
      // bombear frames cuelga el test para siempre (nada dispara el
      // siguiente frame). Se dispara sin esperar y se deja que
      // `pumpAndSettle()` procese tanto el refresco de los providers como
      // la animación de la propia flecha.
      final refreshState = tester.state<RefreshIndicatorState>(
        find.byType(RefreshIndicator),
      );
      unawaited(refreshState.show());
      await tester.pumpAndSettle();

      expect(channels.pageRequests.length, greaterThan(requestsBefore));
    },
  );
}

class _RecordingNavigatorObserver extends NavigatorObserver {
  Route<dynamic>? lastPushed;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    lastPushed = route;
  }
}
