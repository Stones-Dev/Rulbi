import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/features/channels/channel_providers.dart';
import 'package:iptv_app/features/channels/channel_row.dart';
import 'package:iptv_app/features/search/search_providers.dart';
import 'package:iptv_app/features/search/search_screen.dart';
import 'package:iptv_app/l10n/app_localizations.dart';
import 'package:iptv_core/iptv_core.dart';

/// Búsqueda global (ui-spec §2.11, S5 · Ola 1): debounce, agrupación por
/// tipo, resaltado de coincidencia y estado sin-resultados. `pumpWidget`
/// dentro de `testWidgets` para tener control de tiempo simulado sobre el
/// `Timer` de debounce (ver `search_controller_test.dart`).
final class _FakeChannelSearchPort implements ChannelSearchPort {
  Map<ContentType, List<Channel>> resultsByType = const {};

  @override
  Future<List<Channel>> search(
    String query, {
    ContentType? type,
    Set<String>? sourceIds,
    int limit = 50,
  }) async {
    if (type == null) return resultsByType.values.expand((c) => c).toList();
    return resultsByType[type] ?? const [];
  }
}

void main() {
  Channel channelOf(ContentType type, String name) => Channel(
    ref: ChannelRef(sourceId: 's1', key: name),
    sourceId: 's1',
    type: type,
    name: name,
    url: Uri.parse('http://example.com/$name'),
  );

  Future<_FakeChannelSearchPort> pumpScreen(WidgetTester tester) async {
    final port = _FakeChannelSearchPort();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchChannelsProvider.overrideWithValue(SearchChannels(port)),
          activeSourceIdsProvider.overrideWithValue({'s1'}),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: SearchScreen()),
        ),
      ),
    );
    await tester.pump();
    return port;
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const Key('searchField')), text);
    await tester.pump(const Duration(milliseconds: 200)); // pasa el debounce
    await tester.pump(); // deja resolver el Future de la búsqueda
  }

  testWidgets('campo vacío no muestra nada', (tester) async {
    await pumpScreen(tester);
    expect(find.byType(ChannelRow), findsNothing);
  });

  testWidgets('teclear rápido dispara una sola búsqueda tras el debounce', (
    tester,
  ) async {
    final port = _FakeChannelSearchPort()
      ..resultsByType = {
        ContentType.live: [channelOf(ContentType.live, 'La 1')],
      };
    var searchCalls = 0;
    // Se envuelve el puerto para contar llamadas reales al motor.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchChannelsProvider.overrideWithValue(
            SearchChannels(_CountingPort(port, onCall: () => searchCalls++)),
          ),
          activeSourceIdsProvider.overrideWithValue({'s1'}),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: SearchScreen()),
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byKey(const Key('searchField')), 'l');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.enterText(find.byKey(const Key('searchField')), 'la');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.enterText(find.byKey(const Key('searchField')), 'la 1');
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();

    expect(searchCalls, 3); // grouped() = 3 llamadas (live/vod/series), una vez
    expect(find.text('La 1'), findsOneWidget);
  });

  testWidgets('agrupa resultados bajo Channels/Movies/Series', (tester) async {
    final port = await pumpScreen(tester);
    port.resultsByType = {
      ContentType.live: [channelOf(ContentType.live, 'La 1')],
      ContentType.vod: [channelOf(ContentType.vod, 'Oppenheimer')],
      ContentType.series: [channelOf(ContentType.series, 'Dark')],
    };

    await type(tester, 'a');

    expect(find.text('Channels'), findsOneWidget);
    expect(find.text('Movies'), findsOneWidget);
    expect(find.text('Series'), findsOneWidget);
    expect(find.text('La 1'), findsOneWidget);
    expect(find.text('Oppenheimer'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
  });

  testWidgets('un grupo vacío no muestra su cabecera', (tester) async {
    final port = await pumpScreen(tester);
    port.resultsByType = {
      ContentType.live: [channelOf(ContentType.live, 'La 1')],
    };

    await type(tester, 'la');

    expect(find.text('Channels'), findsOneWidget);
    expect(find.text('Movies'), findsNothing);
    expect(find.text('Series'), findsNothing);
  });

  testWidgets('sin resultados, muestra el mensaje con la consulta', (
    tester,
  ) async {
    await pumpScreen(tester);

    await type(tester, 'xyz');

    expect(find.text('No results for "xyz"'), findsOneWidget);
  });

  testWidgets(
    'pasa la consulta a ChannelRow para resaltar la coincidencia '
    '(la mecánica de resaltado en sí la cubre highlighted_spans_test.dart)',
    (tester) async {
      final port = await pumpScreen(tester);
      port.resultsByType = {
        ContentType.live: [channelOf(ContentType.live, 'La 1 HD')],
      };

      await type(tester, 'la 1');

      final row = tester.widget<ChannelRow>(find.byType(ChannelRow));
      expect(row.highlightQuery, 'la 1');
      expect(row.channel.name, 'La 1 HD');
    },
  );
}

/// Envuelve un [ChannelSearchPort] contando cuántas veces se llama a
/// [search] — usado para verificar que el debounce realmente colapsa
/// varias pulsaciones rápidas en una sola ronda de `grouped()`.
final class _CountingPort implements ChannelSearchPort {
  _CountingPort(this._inner, {required this.onCall});

  final ChannelSearchPort _inner;
  final VoidCallback onCall;

  @override
  Future<List<Channel>> search(
    String query, {
    ContentType? type,
    Set<String>? sourceIds,
    int limit = 50,
  }) {
    onCall();
    return _inner.search(query, type: type, sourceIds: sourceIds, limit: limit);
  }
}
