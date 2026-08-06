import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/features/channels/channel_providers.dart';
import 'package:iptv_app/features/search/search_controller.dart';
import 'package:iptv_app/features/search/search_providers.dart';
import 'package:iptv_core/iptv_core.dart';

/// `SearchController` (ui-spec §2.11, S5 · Ola 1): debounce de 150 ms +
/// descarte de resultados obsoletos. `testWidgets`, no `test`, aunque no
/// hay ningún widget: `flutter_test` envuelve el cuerpo en una zona de
/// tiempo simulado (`FakeAsync`), la única forma de controlar el `Timer`
/// del debounce con `tester.pump(duration)` sin esperas reales.
/// Fake de `ChannelSearchPort`: cuenta llamadas, registra `sourceIds`, y
/// puede simular latencia (`delay`) para probar el descarte de resultados
/// obsoletos.
final class _FakeChannelSearchPort implements ChannelSearchPort {
  int callCount = 0;
  Set<String>? lastSourceIds;
  Duration delay = Duration.zero;
  List<Channel> Function(String query)? resultsFor;

  @override
  Future<List<Channel>> search(
    String query, {
    ContentType? type,
    Set<String>? sourceIds,
    int limit = 50,
  }) async {
    callCount++;
    lastSourceIds = sourceIds;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    final all = resultsFor?.call(query) ?? const <Channel>[];
    return type == null ? all : all.where((c) => c.type == type).toList();
  }
}

void main() {
  final live1 = Channel(
    ref: const ChannelRef(sourceId: 's1', key: 'la1'),
    sourceId: 's1',
    type: ContentType.live,
    name: 'La 1',
    url: Uri.parse('http://example.com/la1'),
  );

  ProviderContainer buildContainer(_FakeChannelSearchPort port) {
    final container = ProviderContainer(
      overrides: [
        searchChannelsProvider.overrideWithValue(SearchChannels(port)),
        activeSourceIdsProvider.overrideWithValue({'s1'}),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  testWidgets('consulta vacía deja el estado en idle sin llamar al puerto', (
    tester,
  ) async {
    final port = _FakeChannelSearchPort();
    final container = buildContainer(port);

    container.read(searchControllerProvider.notifier).queryChanged('   ');
    await tester.pump(const Duration(milliseconds: 200));

    expect(container.read(searchControllerProvider), isA<SearchIdle>());
    expect(port.callCount, 0);
  });

  testWidgets('espera el debounce antes de llamar al puerto', (tester) async {
    final port = _FakeChannelSearchPort()..resultsFor = (_) => [live1];
    final container = buildContainer(port);

    container.read(searchControllerProvider.notifier).queryChanged('la');
    expect(container.read(searchControllerProvider), isA<SearchLoading>());
    expect(port.callCount, 0);

    await tester.pump(const Duration(milliseconds: 100));
    expect(port.callCount, 0, reason: 'antes de los 150 ms no debe llamar aún');

    await tester.pump(const Duration(milliseconds: 100));
    expect(port.callCount, 3); // grouped() llama una vez por ContentType
    final state = container.read(searchControllerProvider);
    expect(state, isA<SearchResults>());
  });

  testWidgets(
    'teclear rápido reinicia el debounce: una sola búsqueda con la última consulta',
    (tester) async {
      final port = _FakeChannelSearchPort()..resultsFor = (q) => [live1];
      final container = buildContainer(port);
      final notifier = container.read(searchControllerProvider.notifier);

      notifier.queryChanged('l');
      await tester.pump(const Duration(milliseconds: 80));
      notifier.queryChanged('la');
      await tester.pump(const Duration(milliseconds: 80));
      notifier.queryChanged('la 1');
      await tester.pump(const Duration(milliseconds: 150));

      expect(port.callCount, 3); // una sola ronda de grouped(), no tres
      final state = container.read(searchControllerProvider) as SearchResults;
      expect(state.query, 'la 1');
    },
  );

  testWidgets(
    'descarta un resultado obsoleto que llega tarde tras una consulta más nueva',
    (tester) async {
      final port = _FakeChannelSearchPort();
      final container = buildContainer(port);
      final notifier = container.read(searchControllerProvider.notifier);

      // La primera consulta tarda más que la segunda en resolver.
      port
        ..delay = const Duration(milliseconds: 500)
        ..resultsFor = (q) => [live1];
      notifier.queryChanged('lenta');
      await tester.pump(const Duration(milliseconds: 150)); // dispara la búsqueda

      port.delay = Duration.zero;
      notifier.queryChanged('rapida');
      await tester.pump(const Duration(milliseconds: 150)); // dispara y resuelve

      // La respuesta de 'rapida' ya está en el estado.
      var state = container.read(searchControllerProvider) as SearchResults;
      expect(state.query, 'rapida');

      // Cuando 'lenta' por fin resuelve, no debe pisar el resultado de
      // 'rapida' (ya obsoleto).
      await tester.pump(const Duration(milliseconds: 500));
      state = container.read(searchControllerProvider) as SearchResults;
      expect(state.query, 'rapida');
    },
  );

  testWidgets('pasa las fuentes activas al puerto', (tester) async {
    final port = _FakeChannelSearchPort()..resultsFor = (_) => [live1];
    final container = buildContainer(port);

    container.read(searchControllerProvider.notifier).queryChanged('la 1');
    await tester.pump(const Duration(milliseconds: 150));

    expect(port.lastSourceIds, {'s1'});
  });
}
