import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_protocols/src/xtream/xtream_category.dart';
import 'package:iptv_protocols/src/xtream/xtream_client.dart';
import 'package:iptv_protocols/src/xtream/xtream_failure.dart';
import 'package:iptv_protocols/src/xtream/xtream_mapper.dart';
import 'package:test/test.dart';

import 'support/fake_xtream_transport.dart';

void main() {
  group('XtreamClient — categorías (3 actions, fixtures reales)', () {
    test('get_live_categories: 1 categoría "Noticias"', () async {
      final client = _client(FakeXtreamTransport());
      final result = await client.liveCategories();

      final categories = (result as XtreamOk<List<XtreamCategory>>).value;
      expect(categories, hasLength(1));
      expect(categories.single.id, '1544024662');
      expect(categories.single.name, 'Noticias');
      expect(categories.single.parentId, 0);
    });

    test('get_vod_categories: 1 categoría "Peliculas"', () async {
      final client = _client(FakeXtreamTransport());
      final result = await client.vodCategories();

      final categories = (result as XtreamOk<List<XtreamCategory>>).value;
      expect(categories.single.name, 'Peliculas');
    });

    test('get_series_categories: 1 categoría "Series"', () async {
      final client = _client(FakeXtreamTransport());
      final result = await client.seriesCategories();

      final categories = (result as XtreamOk<List<XtreamCategory>>).value;
      expect(categories.single.name, 'Series');
    });

    test('{} en vez de [] (cuenta sin contenido de ese tipo) -> lista vacía, no error', () async {
      final fake = FakeXtreamTransport()..enqueue('get_vod_categories', jsonResponse({}));
      final client = _client(fake);

      final result = await client.vodCategories();

      expect((result as XtreamOk<List<XtreamCategory>>).value, isEmpty);
    });

    test('respuesta no-lista y no-objeto-vacío -> XtreamMalformed', () async {
      final fake = FakeXtreamTransport()
        ..enqueue('get_vod_categories', jsonResponse({'error': 'unexpected'}));
      final client = _client(fake);

      final result = await client.vodCategories();

      expect((result as XtreamErr<List<XtreamCategory>>).failure, isA<XtreamMalformed>());
    });
  });

  group('XtreamMapper.categoryToCore', () {
    test('deriva un Category estable a partir del nombre, no del category_id crudo', () {
      const category = XtreamCategory(id: '1544024662', name: 'Noticias', parentId: 0);

      final core = XtreamMapper.categoryToCore(
        sourceId: 'src-1',
        category: category,
        type: ContentType.live,
      );

      expect(core.sourceId, 'src-1');
      expect(core.type, ContentType.live);
      expect(core.name, 'Noticias');
      // Mismo criterio que Category.derive con group-title de M3U: el id
      // final es determinista por sourceId+nombre normalizado, no el
      // category_id crudo del panel.
      expect(core.id, Category.derive(sourceId: 'src-1', type: ContentType.live, name: 'Noticias').id);
    });
  });
}

XtreamClient _client(FakeXtreamTransport transport) => XtreamClient(
  host: Uri.parse('http://127.0.0.1:8081'),
  username: 'test',
  password: 'test',
  transport: transport,
);
