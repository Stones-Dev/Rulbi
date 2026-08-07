import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/features/catalog/catalog_info_providers.dart';
import 'package:iptv_app/features/catalog/vod_detail_screen.dart';
import 'package:iptv_app/features/sources/source_providers.dart';
import 'package:iptv_app/l10n/app_localizations.dart';
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
  }) => jsonEncode({
    'info': {
      'plot': plot,
      'genre': genre,
      'rating': rating,
      'releasedate': releaseDate,
      'duration_secs': durationSecs,
      'cover_big': 'http://panel.example.com/covers/oppenheimer.jpg',
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
    expect(find.textContaining('180 min'), findsOneWidget);
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

    expect(find.widgetWithText(ElevatedButton, 'Play'), findsOneWidget);
  });
}
