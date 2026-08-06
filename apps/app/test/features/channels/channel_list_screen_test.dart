import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/features/channels/channel_list_screen.dart';
import 'package:iptv_app/features/channels/channel_row.dart';
import 'package:iptv_app/features/sources/source_providers.dart';
import 'package:iptv_app/l10n/app_localizations.dart';
import 'package:iptv_core/iptv_core.dart';

import '../sources/_helpers/fakes.dart';
import '_helpers/fake_channel_repository.dart';

/// S5 · Ola 1 (ui-spec §2.3): listado virtualizado de canales sobre
/// `ChannelPageCache`. Repo falso con 100k canales sintéticos — el mismo
/// orden de magnitud que el escenario real (RNF-01) — para probar que
/// solo se construyen las filas visibles, no las 100k.
void main() {
  const sourceId = 's1';

  Source activeSource() => Source(
    id: sourceId,
    config: M3uUrlSourceConfig(url: Uri.parse('http://example.com/list.m3u')),
    name: 'Mi lista',
    updatedAt: DateTime.utc(2026, 1, 1),
  );

  Channel channelAt(int i, {String? categoryId}) => Channel(
    ref: ChannelRef(sourceId: sourceId, key: 'canal-$i'),
    sourceId: sourceId,
    categoryId: categoryId,
    type: ContentType.live,
    name: 'Canal ${i.toString().padLeft(6, '0')}',
    url: Uri.parse('http://example.com/$i'),
  );

  Future<FakeChannelListRepository> pumpScreen(
    WidgetTester tester, {
    required List<Channel> channels,
  }) async {
    final sources = FakeSourceRepository();
    await sources.upsert(activeSource());
    final channelRepository = FakeChannelListRepository(channels: channels);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sourceRepositoryProvider.overrideWithValue(sources),
          channelRepositoryProvider.overrideWithValue(channelRepository),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: ChannelListScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return channelRepository;
  }

  testWidgets(
    'con 100k canales, solo construye las filas visibles del viewport',
    (tester) async {
      await pumpScreen(
        tester,
        channels: List.generate(100000, (i) => channelAt(i)),
      );

      // El tamaño de superficie de test por defecto es ~600px de alto;
      // con channelRowExtent=64 caben ~9-10 filas + margen de cacheExtent
      // de Flutter — muy por debajo de las 100k reales.
      expect(find.byType(ChannelRow).evaluate().length, lessThan(50));
      expect(find.text('Canal 000000'), findsOneWidget);
    },
  );

  testWidgets(
    'saltar a un offset profundo carga la página correcta bajo demanda',
    (tester) async {
      final repository = await pumpScreen(
        tester,
        channels: List.generate(100000, (i) => channelAt(i)),
      );

      final scrollableState = tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(const Key('channelListView')),
          matching: find.byType(Scrollable),
        ),
      );
      scrollableState.position.jumpTo(50000 * channelRowExtent);
      await tester.pumpAndSettle();

      expect(find.text('Canal 050000'), findsOneWidget);
      // El salto no debe recorrer secuencialmente las ~250 páginas entre
      // el principio y el destino — solo la del viewport inicial más la
      // del destino tras el salto.
      expect(repository.pageRequests.length, lessThan(10));
    },
  );

  testWidgets('el panel de categorías muestra nombre y contador reales', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      channels: [
        for (var i = 0; i < 3; i++) channelAt(i, categoryId: 'deportes'),
        channelAt(10, categoryId: 'noticias'),
      ],
    );

    expect(find.byKey(const Key('categoryTile.deportes')), findsOneWidget);
    expect(find.byKey(const Key('categoryTile.noticias')), findsOneWidget);

    final deportesTile = tester.widget<ListTile>(
      find.descendant(
        of: find.byKey(const Key('categoryTile.deportes')),
        matching: find.byType(ListTile),
      ),
    );
    expect((deportesTile.trailing as Text).data, '3');

    // Pseudo-categoría "Todas": incluye los 4 canales, no solo los
    // agrupados en una categoría.
    final allTile = tester.widget<ListTile>(
      find.descendant(
        of: find.byKey(const Key('categoryTile.all')),
        matching: find.byType(ListTile),
      ),
    );
    expect((allTile.trailing as Text).data, '4');
  });

  testWidgets(
    'seleccionar una categoría filtra el listado (ui-spec §2.3)',
    (tester) async {
      await pumpScreen(
        tester,
        channels: [
          channelAt(1, categoryId: 'deportes'),
          channelAt(2, categoryId: 'noticias'),
        ],
      );

      expect(find.text('Canal 000001'), findsOneWidget);
      expect(find.text('Canal 000002'), findsOneWidget);

      await tester.tap(find.byKey(const Key('categoryTile.noticias')));
      await tester.pumpAndSettle();

      expect(find.text('Canal 000001'), findsNothing);
      expect(find.text('Canal 000002'), findsOneWidget);
    },
  );

  testWidgets('una fila de canal muestra el anillo de foco al recibir foco', (
    tester,
  ) async {
    final channel = channelAt(0);
    await pumpScreen(tester, channels: [channel]);

    // Localiza el `Container` exacto de la fila por su key (no por tipo:
    // `_LogoFallback` también es un `Container`, y depender del orden de
    // `find.descendant` para desambiguar sería frágil).
    final rowContainerFinder = find.byKey(
      Key('channelRow.${channel.ref.serialized}'),
    );
    // El ancestro `Focus` más cercano es el propio de `ChannelRow` — hay
    // otros más arriba en el árbol (Scaffold/MaterialApp), por eso
    // `.first` y no un `tester.widget` que exige coincidencia única.
    final focusWidget = tester
        .widgetList<Focus>(
          find.ancestor(of: rowContainerFinder, matching: find.byType(Focus)),
        )
        .first;

    focusWidget.focusNode!.requestFocus();
    await tester.pump();
    await tester.pump();

    final container = tester.widget<Container>(rowContainerFinder);
    final decoration = container.decoration as BoxDecoration?;
    expect(decoration?.border, isNotNull);
  });

  testWidgets('sin canales en la sección, muestra el estado vacío', (
    tester,
  ) async {
    await pumpScreen(tester, channels: const []);

    expect(find.text('No channels yet'), findsOneWidget);
  });
}
