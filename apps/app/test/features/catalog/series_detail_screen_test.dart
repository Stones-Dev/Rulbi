import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/features/catalog/catalog_info_providers.dart';
import 'package:iptv_app/features/catalog/series_detail_screen.dart';
import 'package:iptv_app/features/sources/source_providers.dart';
import 'package:iptv_app/l10n/app_localizations.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_tokens/iptv_tokens.dart';

import '../../_helpers/fake_favorites_repository.dart';
import '../home/_helpers/fake_watch_state_repository.dart';
import '../sources/_helpers/fakes.dart';
import '_helpers/fake_xtream_transport.dart';

/// `SeriesDetailScreen` (ui-spec §2.7, S6, Bloque D): selector de
/// temporada + lista de episodios + "Continuar T{n}E{n}".
void main() {
  const sourceId = 's1';

  Source xtreamSource() => Source(
    id: sourceId,
    config: XtreamSourceConfig(host: Uri.parse('http://panel.example.com'), username: 'user'),
    name: 'Mi panel',
    updatedAt: DateTime.utc(2026, 1, 1),
  );

  Channel seriesChannel({String seriesId = '7'}) => Channel(
    ref: ChannelRef(sourceId: sourceId, key: 'series-$seriesId'),
    sourceId: sourceId,
    type: ContentType.series,
    name: 'Chernobyl (import)',
    url: Uri.parse('xtream://$sourceId/series-catalog/$seriesId'),
    metadata: {'x-xtream-series-id': seriesId},
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

  /// Mismo motivo que `primeVodInfo` en `vod_detail_screen_test.dart`:
  /// `XtreamClient.seriesInfo` decodifica dentro de `Isolate.run`, fuera
  /// de la zona async falsa de `pumpAndSettle()`.
  Future<void> primeSeriesInfo(WidgetTester tester, ProviderContainer container, Channel channel) =>
      tester.runAsync(() => container.read(seriesInfoProvider(channel).future));

  Widget wrap(ProviderContainer container, Channel channel) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SeriesDetailScreen(channel: channel),
      ),
    );
  }

  /// El backdrop+póster de `DetailHero` (S6.5 paso 8: 340+180px antes de
  /// que arranque el contenido) + cabecera + acciones + chips ya superan
  /// el alto de superficie por defecto de un test (~600 px) — sin
  /// ampliarla, los `_EpisodeRow` quedan fuera del árbol montado por el
  /// `SingleChildScrollView` y nunca se montan (un widget fuera de vista
  /// no aparece en el árbol de Elements, así que `find.text` no los
  /// encuentra aunque existan como dato). Se amplía aquí en vez de
  /// scrollear en cada test — más alto que antes del rediseño (2600), el
  /// hero a sangre desplaza todo hacia abajo.
  Future<void> pumpSeries(WidgetTester tester, ProviderContainer container, Channel channel) async {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(wrap(container, channel));
    await tester.pumpAndSettle();
  }

  String seriesInfoBody({
    String name = 'Chernobyl',
    String plot = 'La catástrofe nuclear de 1986.',
    String genre = 'Drama',
    String rating = '9.4',
  }) => jsonEncode({
    'info': {'name': name, 'plot': plot, 'genre': genre, 'rating': rating},
    'seasons': [
      {'season_number': 1, 'name': 'Temporada 1'},
      {'season_number': 2, 'name': 'Temporada 2'},
    ],
    'episodes': {
      '1': [
        {
          'id': '101',
          'episode_num': 1,
          'title': '1:23:45',
          'container_extension': 'mp4',
          'info': {'duration_secs': 3600},
        },
        {
          'id': '102',
          'episode_num': 2,
          'title': 'Please Remain Calm',
          'container_extension': 'mp4',
          'info': {'duration_secs': 3300},
        },
      ],
      '2': [
        {
          'id': '201',
          'episode_num': 1,
          'title': 'Open Wide, O Earth',
          'container_extension': 'mp4',
          'info': {'duration_secs': 3400},
        },
      ],
    },
  });

  testWidgets('con ficha completa: título, género, rating, sinopsis y episodios de T1', (tester) async {
    final setup = buildContainer(source: xtreamSource());
    setup.transport.respond('get_series_info', seriesInfoBody());
    final channel = seriesChannel();

    await primeSeriesInfo(tester, setup.container, channel);
    await pumpSeries(tester, setup.container, channel);

    expect(find.text('Chernobyl'), findsWidgets);
    expect(find.textContaining('Drama'), findsOneWidget);
    expect(find.textContaining('★ 9.4'), findsOneWidget);
    expect(find.text('La catástrofe nuclear de 1986.'), findsOneWidget);
    // S6.5 paso 8: el título de la fila pasa a "E{n} · {título}" (frame
    // Figma 44:19: "E1 · Ruido de fondo"), ya no el título suelto.
    expect(find.text('E1 · 1:23:45'), findsOneWidget);
    expect(find.text('E2 · Please Remain Calm'), findsOneWidget);
    // T2 no está seleccionada por defecto (T1 es la primera).
    expect(find.text('E1 · Open Wide, O Earth'), findsNothing);
  });

  testWidgets('sin ficha (fuente M3U): fallback sin reventar, sin selector de temporada', (tester) async {
    final channel = Channel(
      ref: const ChannelRef(sourceId: 'm3u-1', key: 'series-1'),
      sourceId: 'm3u-1',
      type: ContentType.series,
      name: 'Serie sin panel',
      url: Uri.parse('http://cdn.example.com/series'),
      metadata: const {'x-xtream-genre': 'Comedia'},
    );
    final setup = buildContainer(); // sin fuente registrada -> sin ficha

    await pumpSeries(tester, setup.container, channel);

    expect(find.text('Serie sin panel'), findsWidgets);
    expect(find.textContaining('Comedia'), findsOneWidget);
    expect(find.byKey(const Key('seriesDetail.seasonSelector')), findsNothing);
    expect(find.byKey(const Key('seriesDetail.continue')), findsNothing);
  });

  testWidgets('caché: dos aperturas de la misma ficha solo piden get_series_info una vez', (tester) async {
    final setup = buildContainer(source: xtreamSource());
    setup.transport.respond('get_series_info', seriesInfoBody());
    final channel = seriesChannel();

    await primeSeriesInfo(tester, setup.container, channel);
    await pumpSeries(tester, setup.container, channel);
    expect(setup.transport.callsFor('get_series_info'), 1);

    await pumpSeries(tester, setup.container, channel);
    expect(setup.transport.callsFor('get_series_info'), 1);
  });

  testWidgets('el selector de temporada cambia la lista de episodios', (tester) async {
    final setup = buildContainer(source: xtreamSource());
    setup.transport.respond('get_series_info', seriesInfoBody());
    final channel = seriesChannel();

    await primeSeriesInfo(tester, setup.container, channel);
    await pumpSeries(tester, setup.container, channel);

    expect(find.text('E2 · Please Remain Calm'), findsOneWidget);
    expect(find.text('E1 · Open Wide, O Earth'), findsNothing);

    // S6.5 paso 8: el selector pasa de `DropdownButton` a chips — se toca
    // el chip de la temporada directamente, ya no hay menú que abrir.
    await tester.tap(find.byKey(const Key('seriesDetail.season.2')));
    await tester.pumpAndSettle();

    expect(find.text('E2 · Please Remain Calm'), findsNothing);
    expect(find.text('E1 · Open Wide, O Earth'), findsOneWidget);
  });

  testWidgets('"Continuar T{n}E{n}" apunta al episodio con progreso real más reciente', (tester) async {
    final setup = buildContainer(source: xtreamSource());
    setup.transport.respond('get_series_info', seriesInfoBody());
    final channel = seriesChannel();
    await primeSeriesInfo(tester, setup.container, channel);

    // Episodio T2E1 (id 201) tiene progreso más reciente que T1E2 (id 102)
    // — el botón debe apuntar a T2E1, no al primero por orden de lectura.
    setup.watchState.seed(
      WatchState(
        channel: const ChannelRef(sourceId: sourceId, key: 'xtream://$sourceId/series/102'),
        position: const Duration(minutes: 10),
        duration: const Duration(minutes: 55),
        updatedAt: DateTime.utc(2026, 8, 1),
      ),
    );
    setup.watchState.seed(
      WatchState(
        channel: const ChannelRef(sourceId: sourceId, key: 'xtream://$sourceId/series/201'),
        position: const Duration(minutes: 5),
        duration: const Duration(minutes: 57),
        updatedAt: DateTime.utc(2026, 8, 7),
      ),
    );

    await pumpSeries(tester, setup.container, channel);

    expect(find.text('Continue S2E1'), findsOneWidget);
  });

  testWidgets('sin ningún progreso, "Continuar" apunta a la primera temporada, episodio 1', (tester) async {
    final setup = buildContainer(source: xtreamSource());
    setup.transport.respond('get_series_info', seriesInfoBody());
    final channel = seriesChannel();

    await primeSeriesInfo(tester, setup.container, channel);
    await pumpSeries(tester, setup.container, channel);

    expect(find.text('Continue S1E1'), findsOneWidget);
  });

  // S6.5 paso 8 — miniatura de episodio (XtreamEpisode.stillUrl).
  testWidgets('con movie_image poblado, la miniatura del episodio usa stillUrl', (tester) async {
    final setup = buildContainer(source: xtreamSource());
    setup.transport.respond(
      'get_series_info',
      jsonEncode({
        'info': {'name': 'Chernobyl', 'plot': 'x', 'genre': 'Drama', 'rating': '9.4'},
        'seasons': [
          {'season_number': 1, 'name': 'Temporada 1'},
        ],
        'episodes': {
          '1': [
            {
              'id': '101',
              'episode_num': 1,
              'title': 'Uno Veintitrés Cuarenta y Cinco',
              'container_extension': 'mp4',
              'info': {
                'duration_secs': 3600,
                'movie_image': 'https://panel.example.com/stills/chernobyl_e1.jpg',
              },
            },
          ],
        },
      }),
    );
    final channel = seriesChannel();

    await primeSeriesInfo(tester, setup.container, channel);
    await pumpSeries(tester, setup.container, channel);

    final image = tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage).last);
    expect(image.imageUrl, 'https://panel.example.com/stills/chernobyl_e1.jpg');
  });

  testWidgets('sin movie_image, la miniatura del episodio cae al fallback (icono)', (tester) async {
    final setup = buildContainer(source: xtreamSource());
    setup.transport.respond('get_series_info', seriesInfoBody());
    final channel = seriesChannel();

    await primeSeriesInfo(tester, setup.container, channel);
    await pumpSeries(tester, setup.container, channel);

    // Ningún episodio de `seriesInfoBody()` trae `movie_image` — cero
    // `CachedNetworkImage` en toda la ficha (ni backdrop/póster: sin
    // cover_url tampoco), solo iconos de fallback.
    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(find.byIcon(Symbols.movie_rounded), findsWidgets);
  });
}
