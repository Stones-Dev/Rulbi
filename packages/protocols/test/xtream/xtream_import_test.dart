import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_protocols/src/xtream/xtream_client.dart';
import 'package:test/test.dart';

import 'support/fake_xtream_transport.dart';

/// T1.4: `importChannels()` de punta a punta contra los 9 fixtures reales
/// — el equivalente Xtream de `parseM3u`, mismo contrato de salida
/// (`Stream<Channel>` + informe de tolerancia) para que entre sin
/// fricción en `ManageSources.addSource`. S5.5 Bloque C añade el catálogo
/// de series (`get_series`/`get_series_categories`), también presentes
/// entre los 9 fixtures reales de T1.1 (1 serie, sin episodios).
void main() {
  group('XtreamClient.importChannels — contra los 9 fixtures reales', () {
    test('emite 2 canales live + 1 vod + 1 serie, con categorías resueltas por nombre', () async {
      final client = _client(FakeXtreamTransport());

      final outcome = client.importChannels(sourceId: 'src-1');
      final channels = await outcome.channels.toList();
      final report = await outcome.report;

      expect(channels, hasLength(4));
      expect(channels.where((c) => c.type == ContentType.live), hasLength(2));
      expect(channels.where((c) => c.type == ContentType.vod), hasLength(1));
      expect(channels.where((c) => c.type == ContentType.series), hasLength(1));

      final canalUno = channels.firstWhere((c) => c.name == 'Canal Uno HD');
      expect(canalUno.sourceId, 'src-1');
      // La categoría se resuelve por nombre (Noticias), no por el
      // category_id crudo — mismo criterio que Category.derive con
      // group-title de M3U.
      expect(canalUno.categoryId, Category.derive(sourceId: 'src-1', type: ContentType.live, name: 'Noticias').id);

      final pelicula = channels.firstWhere((c) => c.type == ContentType.vod);
      expect(pelicula.name, 'Pelicula de Prueba');
      expect(pelicula.categoryId, Category.derive(sourceId: 'src-1', type: ContentType.vod, name: 'Peliculas').id);

      final serie = channels.firstWhere((c) => c.type == ContentType.series);
      expect(serie.name, 'Serie de Prueba');
      expect(serie.categoryId, Category.derive(sourceId: 'src-1', type: ContentType.series, name: 'Series').id);
      expect(serie.url.toString(), 'xtream://src-1/series-catalog/115941465');

      expect(report.parsedLive, 2);
      expect(report.parsedVod, 1);
      expect(report.parsedSeries, 1);
      expect(report.discardedCount, 0);
    });

    test('no empieza a pedir nada hasta que alguien escucha el stream', () async {
      final fake = FakeXtreamTransport();
      final client = _client(fake);

      final outcome = client.importChannels(sourceId: 'src-1');
      // Sin await ni listen todavía.
      await Future<void>.delayed(Duration.zero);
      expect(fake.callCount('get_live_streams'), 0);

      await outcome.channels.toList();
      expect(fake.callCount('get_live_streams'), 1);
    });

    test('un 500 en get_vod_streams no aborta el import de los canales live (P7)', () async {
      final fake = FakeXtreamTransport()..enqueue('get_vod_streams', rawResponse([], statusCode: 500));
      final client = _client(fake);

      final outcome = client.importChannels(sourceId: 'src-1');
      final channels = await outcome.channels.toList();
      final report = await outcome.report;

      expect(channels.where((c) => c.type == ContentType.live), hasLength(2));
      expect(channels.where((c) => c.type == ContentType.vod), isEmpty);
      expect(report.parsedVod, 0);
      expect(report.discardedCount, 1);
      expect(report.discarded.single.action, 'get_vod_streams');
    });

    test('fallo de categorías live no impide importar los streams, degrada al category_id crudo', () async {
      final fake = FakeXtreamTransport()..enqueue('get_live_categories', rawResponse([], statusCode: 500));
      final client = _client(fake);

      final outcome = client.importChannels(sourceId: 'src-1');
      final channels = await outcome.channels.toList();
      final report = await outcome.report;

      final canalUno = channels.firstWhere((c) => c.name == 'Canal Uno HD');
      expect(
        canalUno.categoryId,
        Category.derive(sourceId: 'src-1', type: ContentType.live, name: '1544024662').id,
        reason: 'sin nombre de categoría disponible, se degrada al category_id crudo',
      );
      expect(report.discarded.any((d) => d.action == 'get_live_categories'), isTrue);
    });
  });

  group('XtreamImportReport', () {
    test('cesión del event loop cada cessionInterval canales (RNF-01)', () async {
      final live = [
        for (var i = 0; i < 1200; i++) {'stream_id': i, 'name': 'Canal $i', 'category_id': null},
      ];
      final fake = FakeXtreamTransport()
        ..enqueue('get_live_streams', jsonResponse(live))
        ..enqueue('get_vod_streams', jsonResponse(<Object?>[]));
      final client = _client(fake);

      final outcome = client.importChannels(sourceId: 'src-1', cessionInterval: 100);
      final channels = await outcome.channels.toList();

      expect(channels.where((c) => c.type == ContentType.live), hasLength(1200));
    });
  });
}

XtreamClient _client(FakeXtreamTransport transport) => XtreamClient(
  host: Uri.parse('http://127.0.0.1:8081'),
  username: 'test',
  password: 'test',
  transport: transport,
);
