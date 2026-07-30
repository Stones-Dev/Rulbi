import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_data/src/db/content_hash.dart';

/// T1.6b: el criterio de "cambió" del upsert diferencial no compara el
/// `Channel` completo (traería `metadataJson` de las 100k filas existentes),
/// compara este hash. Ver diseño en el handoff/plan de T1.6b.
void main() {
  group('channelContentHash', () {
    ChannelFields sample({
      String? categoryId = 'cat-1',
      String contentType = 'live',
      String name = 'España TV',
      String url = 'http://example.com/a',
      String? tvgId = 'es1',
      String? logo,
      String metadataJson = '{"group-title":"General"}',
    }) => ChannelFields(
      categoryId: categoryId,
      contentType: contentType,
      name: name,
      url: url,
      tvgId: tvgId,
      logo: logo,
      metadataJson: metadataJson,
    );

    test('es determinista: mismos campos, mismo hash', () {
      expect(channelContentHash(sample()), channelContentHash(sample()));
    });

    test('cambia si cambia el nombre', () {
      expect(
        channelContentHash(sample(name: 'España TV')),
        isNot(channelContentHash(sample(name: 'Otro nombre'))),
      );
    });

    test('cambia si cambia solo la url', () {
      expect(
        channelContentHash(sample(url: 'http://example.com/a')),
        isNot(channelContentHash(sample(url: 'http://example.com/b'))),
      );
    });

    test('cambia si cambia solo metadataJson (group-title)', () {
      expect(
        channelContentHash(sample(metadataJson: '{"group-title":"General"}')),
        isNot(
          channelContentHash(sample(metadataJson: '{"group-title":"Deportes"}')),
        ),
      );
    });

    test('cambia si cambia solo tvgId', () {
      expect(
        channelContentHash(sample(tvgId: 'es1')),
        isNot(channelContentHash(sample(tvgId: 'es2'))),
      );
    });

    test('cambia si cambia solo categoryId', () {
      expect(
        channelContentHash(sample(categoryId: 'cat-1')),
        isNot(channelContentHash(sample(categoryId: 'cat-2'))),
      );
    });

    test('cambia si cambia solo contentType (reclasificación live -> vod)', () {
      expect(
        channelContentHash(sample(contentType: 'live')),
        isNot(channelContentHash(sample(contentType: 'vod'))),
      );
    });

    test('cambia si cambia solo logo (incluida la transición null -> valor)', () {
      expect(
        channelContentHash(sample(logo: null)),
        isNot(channelContentHash(sample(logo: 'http://example.com/logo.png'))),
      );
    });

    test('null vs cadena vacía no colisionan por construcción', () {
      expect(
        channelContentHash(sample(categoryId: null)),
        isNot(channelContentHash(sample(categoryId: ''))),
      );
    });

    test(
      'un delimitador interno no hace colisionar dos particiones de campos '
      'distintas ("a", "b") vs ("a\\x1fb", "")',
      () {
        final a = channelContentHash(
          sample(tvgId: 'a', logo: 'b'),
        );
        final b = channelContentHash(
          sample(tvgId: 'a\x1fb', logo: ''),
        );
        expect(a, isNot(b));
      },
    );

    test('una barra invertida literal en un campo no rompe el escape', () {
      expect(
        channelContentHash(sample(name: r'Canal \ raro')),
        channelContentHash(sample(name: r'Canal \ raro')),
      );
      expect(
        channelContentHash(sample(name: r'Canal \ raro')),
        isNot(channelContentHash(sample(name: 'Canal  raro'))),
      );
    });

    test('no depende de sourceId/refKey (no forman parte de la firma)', () {
      // ChannelFields no expone sourceId/refKey: es la garantía en el tipo,
      // no solo en el test — ver diseño en content_hash.dart.
      expect(channelContentHash(sample()), isA<String>());
    });
  });
}
