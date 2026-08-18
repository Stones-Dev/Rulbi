import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/features/catalog/catalog_info_providers.dart';
import 'package:iptv_app/features/catalog/vod_detail_screen.dart';
import 'package:iptv_app/features/sources/source_providers.dart';
import 'package:iptv_app/l10n/app_localizations.dart';
import 'package:iptv_app/widgets/detail_hero.dart';
import 'package:iptv_core/iptv_core.dart';

import '../../_helpers/fake_favorites_repository.dart';
import '../home/_helpers/fake_watch_state_repository.dart';
import '../sources/_helpers/fakes.dart';
import '_helpers/fake_xtream_transport.dart';

/// `VodDetailScreen` (ui-spec §2.6, S6, Bloque D).
void main() {
  const sourceId = 's1';

  Source xtreamSource() => Source(
    id: sourceId,
    config: XtreamSourceConfig(host: Uri.parse('http://panel.example.com'), username: 'user'),
    name: 'Mi panel',
    updatedAt: DateTime.utc(2026, 1, 1),
  );

  Channel vodChannel({String streamId = '42'}) => Channel(
    ref: ChannelRef(sourceId: sourceId, key: 'movie-$streamId'),
    sourceId: sourceId,
    type: ContentType.vod,
    name: 'Oppenheimer (import)',
    url: Uri.parse('xtream://$sourceId/movie/$streamId.mp4'),
    metadata: {'x-xtream-stream-id': streamId},
  );

  ({ProviderContainer container, FakeXtreamTransport transport, FakeWatchStateRepository watchState})
  buildContainer({Source? source}) {
    final sources = FakeSourceRepository();
    if (source != null) unawaited(sources.upsert(source));
    final secureStore = FakeSecureCredentialStore();
    if (source != null) unawaited(secureStore.save(sourceId, 'super-secreta'));
    final watchState = FakeWatchStateRepository();
    final transport = FakeXtreamTransport();

    final container = ProviderContainer(
      overrides: [
        sourceRepositoryProvider.overrideWithValue(sources),
        secureCredentialStoreProvider.overrideWithValue(secureStore),
        watchStateRepositoryProvider.overrideWithValue(watchState),
        favoritesRepositoryProvider.overrideWithValue(FakeFavoritesRepository()),
        xtreamInfoTransportFactoryProvider.overrideWithValue(() => transport),
      ],
    );
    return (container: container, transport: transport, watchState: watchState);
  }

  /// `XtreamClient.vodInfo` decodifica el cuerpo dentro de `Isolate.run`
  /// (RNF-01, `packages/protocols`) — un `Isolate` real no corre dentro
  /// de la zona async falsa que usa `WidgetTester.pumpAndSettle()`. Se
  /// resuelve aquí, en la zona real (`tester.runAsync`), **antes** de
  /// montar el widget: así `VodDetailScreen` siempre lo lee ya cacheado,
  /// sin depender de que `pumpAndSettle` detecte un `Future` que vive
  /// fuera de su reloj simulado.
  Future<void> primeVodInfo(WidgetTester tester, ProviderContainer container, Channel channel) =>
      tester.runAsync(() => container.read(vodInfoProvider(channel).future));

  Widget wrap(ProviderContainer container, Channel channel) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: VodDetailScreen(channel: channel),
      ),
    );
  }

  String vodInfoBody({
    String name = 'Oppenheimer',
    String plot = 'Historia del físico J. Robert Oppenheimer.',
    String genre = 'Drama, Historia',
    String rating = '8.9',
    String releaseDate = '2023-07-21',
    int durationSecs = 10800,
    String? backdropUrl,
  }) => jsonEncode({
    'info': {
      'plot': plot,
      'genre': genre,
      'rating': rating,
      'releasedate': releaseDate,
      'duration_secs': durationSecs,
      'cover_big': 'http://panel.example.com/covers/oppenheimer.jpg',
      if (backdropUrl != null) 'backdrop_path': [backdropUrl],
    },
    'movie_data': {'stream_id': '42', 'name': name, 'category_id': '1'},
  });

  testWidgets('con ficha completa: título, año, duración, género, rating y sinopsis', (tester) async {
    final setup = buildContainer(source: xtreamSource());
    setup.transport.respond('get_vod_info', vodInfoBody());
    final channel = vodChannel();

    await primeVodInfo(tester, setup.container, channel);
    await tester.pumpWidget(wrap(setup.container, channel));
    await tester.pumpAndSettle();

    expect(find.text('Oppenheimer'), findsWidgets);
    expect(find.textContaining('2023'), findsOneWidget);
    // S6.5 paso 7: "180 min" -> "3h 0m" (formatDurationHoursMinutes, frame
    // Figma 43:2 usa "1h 52m", no minutos sueltos para duraciones ≥1h).
    expect(find.textContaining('3h 0m'), findsOneWidget);
    expect(find.textContaining('Drama, Historia'), findsOneWidget);
    expect(find.textContaining('★ 8.9'), findsOneWidget);
    expect(find.text('Historia del físico J. Robert Oppenheimer.'), findsOneWidget);
  });

  testWidgets('sin ficha (fuente M3U): fallback tipográfico con los metadatos del import, sin reventar', (
    tester,
  ) async {
    final channel = Channel(
      ref: const ChannelRef(sourceId: 'm3u-1', key: 'movie-1'),
      sourceId: 'm3u-1',
      type: ContentType.vod,
      name: 'Interstellar (import)',
      url: Uri.parse('http://cdn.example.com/movie.mp4'),
      metadata: const {'x-xtream-genre': 'Sci-Fi', 'x-xtream-rating': '9.1'},
    );
    final setup = buildContainer(); // sin fuente registrada -> sin ficha

    await tester.pumpWidget(wrap(setup.container, channel));
    await tester.pumpAndSettle();

    expect(find.text('Interstellar (import)'), findsWidgets);
    expect(find.textContaining('Sci-Fi'), findsOneWidget);
    expect(find.textContaining('★ 9.1'), findsOneWidget);
    expect(setup.transport.calls, isEmpty);
  });

  testWidgets('caché: dos aperturas de la misma ficha solo piden get_vod_info una vez', (tester) async {
    final setup = buildContainer(source: xtreamSource());
    setup.transport.respond('get_vod_info', vodInfoBody());
    final channel = vodChannel();

    await primeVodInfo(tester, setup.container, channel);
    await tester.pumpWidget(wrap(setup.container, channel));
    await tester.pumpAndSettle();
    expect(setup.transport.callsFor('get_vod_info'), 1);

    // Segunda apertura de la MISMA ficha, mismo container (misma caché de
    // Riverpod) — reutiliza el resultado ya resuelto, sin volver a pedirlo.
    await tester.pumpWidget(wrap(setup.container, channel));
    await tester.pumpAndSettle();
    expect(setup.transport.callsFor('get_vod_info'), 1);
  });

  testWidgets('con progreso guardado: el botón dice Continuar (mm:ss)', (tester) async {
    final setup = buildContainer(source: xtreamSource());
    setup.transport.respond('get_vod_info', vodInfoBody());
    final channel = vodChannel();
    setup.watchState.seed(
      WatchState(
        channel: channel.ref,
        position: const Duration(minutes: 42, seconds: 5),
        duration: const Duration(minutes: 180),
        updatedAt: DateTime.utc(2026, 8, 7),
      ),
    );

    await primeVodInfo(tester, setup.container, channel);
    await tester.pumpWidget(wrap(setup.container, channel));
    await tester.pumpAndSettle();

    expect(find.textContaining('42:05'), findsOneWidget);
  });

  testWidgets('sin progreso guardado: el botón dice Reproducir', (tester) async {
    final setup = buildContainer(source: xtreamSource());
    setup.transport.respond('get_vod_info', vodInfoBody());
    final channel = vodChannel();

    await primeVodInfo(tester, setup.container, channel);
    await tester.pumpWidget(wrap(setup.container, channel));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Play'), findsOneWidget);
  });

  // S6.5 paso 7: DetailHero (backdrop, botón de volver, favorito animado).
  testWidgets('backdrop_path de la ficha se propaga a DetailHero.backdropUrl', (tester) async {
    final setup = buildContainer(source: xtreamSource());
    setup.transport.respond(
      'get_vod_info',
      vodInfoBody(backdropUrl: 'http://panel.example.com/backdrops/oppenheimer.jpg'),
    );
    final channel = vodChannel();

    await primeVodInfo(tester, setup.container, channel);
    await tester.pumpWidget(wrap(setup.container, channel));
    await tester.pumpAndSettle();

    final hero = tester.widget<DetailHero>(find.byType(DetailHero));
    expect(hero.backdropUrl, 'http://panel.example.com/backdrops/oppenheimer.jpg');
  });

  testWidgets('sin backdrop_path: DetailHero.backdropUrl es null (cae a coverUrl difuminado)', (
    tester,
  ) async {
    final setup = buildContainer(source: xtreamSource());
    setup.transport.respond('get_vod_info', vodInfoBody());
    final channel = vodChannel();

    await primeVodInfo(tester, setup.container, channel);
    await tester.pumpWidget(wrap(setup.container, channel));
    await tester.pumpAndSettle();

    final hero = tester.widget<DetailHero>(find.byType(DetailHero));
    expect(hero.backdropUrl, isNull);
    expect(hero.coverUrl, 'http://panel.example.com/covers/oppenheimer.jpg');
  });

  testWidgets('Key(contentDetail.back) hace pop de la ficha', (tester) async {
    final setup = buildContainer(source: xtreamSource());
    setup.transport.respond('get_vod_info', vodInfoBody());
    final channel = vodChannel();
    await primeVodInfo(tester, setup.container, channel);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: setup.container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute<void>(builder: (_) => VodDetailScreen(channel: channel))),
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.byType(VodDetailScreen), findsOneWidget);

    await tester.tap(find.byKey(const Key('contentDetail.back')));
    await tester.pumpAndSettle();
    expect(find.byType(VodDetailScreen), findsNothing);
  });

  testWidgets('el toggle de favorito no rompe el árbol durante la animación de rebote', (tester) async {
    final setup = buildContainer(source: xtreamSource());
    setup.transport.respond('get_vod_info', vodInfoBody());
    final channel = vodChannel();

    await primeVodInfo(tester, setup.container, channel);
    await tester.pumpWidget(wrap(setup.container, channel));
    await tester.pumpAndSettle();

    final favoriteKey = Key('contentDetail.favorite.${channel.ref.serialized}');
    // El backdrop+póster (S6.5 paso 7) empuja el CTA fuera del viewport
    // por defecto del test (800×600) — sin esto, `tap()` avisa de un hit
    // test fuera de pantalla (sigue entregando el evento, pero es ruido
    // evitable, mismo motivo que `pumpSeries` amplía la superficie).
    await tester.ensureVisible(find.byKey(favoriteKey));
    await tester.tap(find.byKey(favoriteKey));
    // A medio camino de la animación de rebote (200ms) — el árbol no debe
    // lanzar ni el botón debe desaparecer mientras `_scale` está en 1.3.
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.byKey(favoriteKey), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
