import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/features/catalog/catalog_screen.dart';
import 'package:iptv_app/features/catalog/poster_card.dart';
import 'package:iptv_app/features/catalog/series_detail_screen.dart';
import 'package:iptv_app/features/catalog/vod_detail_screen.dart';
import 'package:iptv_app/features/sources/source_providers.dart';
import 'package:iptv_app/l10n/app_localizations.dart';
import 'package:iptv_core/iptv_core.dart';

import '../../_helpers/fake_epg_repository.dart';
import '../../_helpers/fake_favorites_repository.dart';
import '../channels/_helpers/fake_channel_repository.dart';
import '../home/_helpers/fake_watch_state_repository.dart';
import '../sources/_helpers/fakes.dart';

/// `CatalogScreen` (ui-spec §2.3.1, S5.5 Bloque D) — mismo patrón que
/// `channel_list_screen_test.dart` (S5 · Ola 1): fakes a mano +
/// `ProviderScope(overrides:)`, sin mockito. `FakeChannelListRepository`
/// ya filtra por `ContentType`, así que sirve tal cual para `vod`/`series`.
void main() {
  const sourceId = 's1';

  Source activeSource() => Source(
    id: sourceId,
    config: XtreamSourceConfig(host: Uri.parse('http://panel.example.com'), username: 'user'),
    name: 'Mi panel',
    updatedAt: DateTime.utc(2026, 1, 1),
  );

  Channel movieAt(int i, {String? categoryId, String? releaseDate}) => Channel(
    ref: ChannelRef(sourceId: sourceId, key: 'movie-$i'),
    sourceId: sourceId,
    categoryId: categoryId,
    type: ContentType.vod,
    name: 'Pelicula ${i.toString().padLeft(3, '0')}',
    url: Uri.parse('xtream://$sourceId/movie/$i'),
    metadata: {'x-xtream-release-date': ?releaseDate},
  );

  Channel seriesAt(int i, {String? categoryId}) => Channel(
    ref: ChannelRef(sourceId: sourceId, key: 'series-$i'),
    sourceId: sourceId,
    categoryId: categoryId,
    type: ContentType.series,
    name: 'Serie ${i.toString().padLeft(3, '0')}',
    url: Uri.parse('xtream://$sourceId/series-catalog/$i'),
  );

  Future<FakeChannelListRepository> pumpScreen(
    WidgetTester tester, {
    required ContentType type,
    required List<Channel> channels,
    FakeFavoritesRepository? favorites,
  }) async {
    final sources = FakeSourceRepository();
    await sources.upsert(activeSource());
    final channelRepository = FakeChannelListRepository(channels: channels);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sourceRepositoryProvider.overrideWithValue(sources),
          channelRepositoryProvider.overrideWithValue(channelRepository),
          favoritesRepositoryProvider.overrideWithValue(favorites ?? FakeFavoritesRepository()),
          epgRepositoryProvider.overrideWithValue(FakeEpgRepository()),
          // VodDetailScreen/SeriesDetailScreen (S6, Bloque D) — sin estos,
          // tocar un póster dispara `iptvDatabaseProvider`/almacén seguro
          // reales (mismo gotcha ya documentado en desktop_shell_test.dart).
          secureCredentialStoreProvider.overrideWithValue(FakeSecureCredentialStore()),
          watchStateRepositoryProvider.overrideWithValue(FakeWatchStateRepository()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: CatalogScreen(type: type)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return channelRepository;
  }

  testWidgets('rejilla de Películas con datos sintéticos: título y póster visibles', (tester) async {
    await pumpScreen(
      tester,
      type: ContentType.vod,
      channels: [movieAt(1), movieAt(2)],
    );

    expect(find.byType(PosterCard), findsNWidgets(2));
    // findsWidgets (no findsOneWidget): sin logo, el fallback tipográfico
    // del póster también pinta el nombre además del título bajo la
    // tarjeta (ver PosterFallback) — dos apariciones legítimas, no un bug.
    expect(find.text('Pelicula 001'), findsWidgets);
    expect(find.text('Pelicula 002'), findsWidgets);
  });

  testWidgets('año: se muestra si x-xtream-release-date está presente, se omite si no', (tester) async {
    await pumpScreen(
      tester,
      type: ContentType.vod,
      channels: [movieAt(1, releaseDate: '2020-05-01'), movieAt(2)],
    );

    expect(find.text('2020'), findsOneWidget);
  });

  testWidgets('rejilla de Series con datos sintéticos', (tester) async {
    await pumpScreen(
      tester,
      type: ContentType.series,
      channels: [seriesAt(1), seriesAt(2), seriesAt(3)],
    );

    expect(find.byType(PosterCard), findsNWidgets(3));
    expect(find.text('Serie 001'), findsWidgets);
  });

  testWidgets('paginación: solo construye lo visible con un catálogo grande', (tester) async {
    await pumpScreen(
      tester,
      type: ContentType.vod,
      channels: List.generate(500, (i) => movieAt(i)),
    );

    expect(find.byType(PosterCard).evaluate().length, lessThan(100));
  });

  testWidgets('catálogo vacío de Películas: estado propio', (tester) async {
    await pumpScreen(tester, type: ContentType.vod, channels: const []);

    expect(find.text('No movies yet'), findsOneWidget);
  });

  testWidgets('catálogo vacío de Series: estado propio, distinto del de Películas', (tester) async {
    await pumpScreen(tester, type: ContentType.series, channels: const []);

    expect(find.text('No series yet'), findsOneWidget);
    expect(find.text('No movies yet'), findsNothing);
  });

  testWidgets('el panel de categorías filtra la rejilla (ui-spec §2.3.1)', (tester) async {
    await pumpScreen(
      tester,
      type: ContentType.vod,
      channels: [
        movieAt(1, categoryId: 'accion'),
        movieAt(2, categoryId: 'comedia'),
      ],
    );

    expect(find.text('Pelicula 001'), findsWidgets);
    expect(find.text('Pelicula 002'), findsWidgets);

    await tester.tap(find.byKey(const Key('categoryTile.comedia')));
    await tester.pumpAndSettle();

    expect(find.text('Pelicula 001'), findsNothing);
    expect(find.text('Pelicula 002'), findsWidgets);
  });

  testWidgets('badge de favorito: refleja favoriteRefsProvider y togglea', (tester) async {
    final channel = movieAt(1);
    final favorites = FakeFavoritesRepository();
    await pumpScreen(tester, type: ContentType.vod, channels: [channel], favorites: favorites);
    // favoriteRefsProvider es un StreamProvider: un pump extra para que
    // resuelva su primer valor tras el pumpAndSettle inicial.
    await tester.pump();

    final favoriteKey = Key('posterCard.favorite.${channel.ref.serialized}');
    expect(find.byKey(favoriteKey), findsOneWidget);
    expect(
      tester.widget<IconButton>(find.byKey(favoriteKey)).icon,
      isA<Icon>().having((i) => i.icon, 'icon', Icons.favorite_border),
    );

    await tester.tap(find.byKey(favoriteKey));
    await tester.pumpAndSettle();

    expect(
      tester.widget<IconButton>(find.byKey(favoriteKey)).icon,
      isA<Icon>().having((i) => i.icon, 'icon', Icons.favorite),
    );
  });

  testWidgets('tocar un póster de Película abre VodDetailScreen con el canal (D6)', (tester) async {
    final channel = movieAt(1);
    await pumpScreen(tester, type: ContentType.vod, channels: [channel]);

    // Único PosterCard en pantalla (un solo canal): sin ambigüedad, a
    // diferencia de buscar por texto (ver PosterFallback más arriba).
    await tester.tap(find.byType(PosterCard));
    await tester.pumpAndSettle();

    expect(find.byType(VodDetailScreen), findsOneWidget);
    // S6.5 paso 7: sin AppBar (DetailHero con backdrop a sangre en su
    // lugar) — el título vive dentro de la propia pantalla, no de un
    // AppBar que ya no existe. `findsWidgets` (no `findsOneWidget`): sin
    // cover_url en este canal sintético, el póster cae a `PosterFallback`,
    // que también pinta el nombre como texto — dos apariciones legítimas,
    // no una regresión.
    expect(
      find.descendant(of: find.byType(VodDetailScreen), matching: find.text('Pelicula 001')),
      findsWidgets,
    );
  });

  testWidgets('tocar un póster de Serie abre SeriesDetailScreen con el canal (D6)', (tester) async {
    final channel = seriesAt(1);
    await pumpScreen(tester, type: ContentType.series, channels: [channel]);

    await tester.tap(find.byType(PosterCard));
    await tester.pumpAndSettle();

    expect(find.byType(SeriesDetailScreen), findsOneWidget);
    // `findsWidgets`, mismo motivo que en el caso de Película arriba.
    expect(
      find.descendant(of: find.byType(SeriesDetailScreen), matching: find.text('Serie 001')),
      findsWidgets,
    );
  });
}
