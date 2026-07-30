import 'dart:convert';
import 'dart:io';

import 'package:iptv_protocols/src/xmltv/xmltv_encoding.dart';
import 'package:test/test.dart';

List<int> _concat(List<List<int>> parts) => parts.expand((p) => p).toList();

Future<String> _decodeAll(List<int> bytes) async {
  final chunks = await decodeXmltvBytes(Stream.value(bytes)).toList();
  return chunks.join();
}

void main() {
  group('decodeXmltvBytes — encoding y gunzip (T1.3, batería 5)', () {
    test('declaración UTF-8 explícita', () async {
      const xml =
          '<?xml version="1.0" encoding="UTF-8"?>'
          '<tv><channel id="a"><display-name>Canal Ñoño</display-name></channel></tv>';
      final decoded = await _decodeAll(utf8.encode(xml));
      expect(decoded, contains('Canal Ñoño'));
    });

    test('declaración ISO-8859-1 con tildes/eñe en bytes Latin-1 reales', () async {
      final prefix = ascii.encode(
        '<?xml version="1.0" encoding="ISO-8859-1"?>'
        '<tv><channel id="a"><display-name>',
      );
      final name = latin1.encode('Canal Ñoño con áéíóú');
      final suffix = ascii.encode('</display-name></channel></tv>');

      final decoded = await _decodeAll(_concat([prefix, name, suffix]));
      expect(decoded, contains('Canal Ñoño con áéíóú'));
    });

    test('BOM UTF-8 gana sobre una declaración contradictoria', () async {
      // La declaración dice ISO-8859-1, pero el contenido real está en
      // UTF-8 con BOM — el BOM tiene prioridad (regla del propio XML).
      const bom = [0xEF, 0xBB, 0xBF];
      const xml =
          '<?xml version="1.0" encoding="ISO-8859-1"?>'
          '<tv><channel id="a"><display-name>Canal Ñoño</display-name></channel></tv>';

      final decoded = await _decodeAll(_concat([bom, utf8.encode(xml)]));
      expect(decoded, contains('Canal Ñoño'));
    });

    test('BOM UTF-16 LE', () async {
      const bom = [0xFF, 0xFE];
      const xml =
          '<tv><channel id="a"><display-name>Canal Ñoño</display-name></channel></tv>';
      final utf16Bytes = <int>[];
      for (final unit in xml.codeUnits) {
        utf16Bytes
          ..add(unit & 0xFF)
          ..add((unit >> 8) & 0xFF);
      }

      final decoded = await _decodeAll(_concat([bom, utf16Bytes]));
      expect(decoded, contains('Canal Ñoño'));
    });

    test('sin declaración ni BOM, con byte Latin-1: fallback UTF-8 estricto → Latin-1', () async {
      final prefix = ascii.encode('<tv><channel id="a"><display-name>');
      final name = latin1.encode('Canal Ñoño');
      final suffix = ascii.encode('</display-name></channel></tv>');

      final decoded = await _decodeAll(_concat([prefix, name, suffix]));
      expect(decoded, contains('Canal Ñoño'));
    });

    test('windows-1252 se aproxima a Latin-1 (documentado, no silencioso)', () async {
      final prefix = ascii.encode(
        '<?xml version="1.0" encoding="windows-1252"?>'
        '<tv><channel id="a"><display-name>',
      );
      final name = latin1.encode('Canal Ñoño');
      final suffix = ascii.encode('</display-name></channel></tv>');

      final decoded = await _decodeAll(_concat([prefix, name, suffix]));
      expect(decoded, contains('Canal Ñoño'));
    });

    test('.gz: gunzip al vuelo antes de detectar encoding', () async {
      const xml =
          '<?xml version="1.0" encoding="UTF-8"?>'
          '<tv><channel id="a"><display-name>Canal Comprimido</display-name></channel></tv>';
      final compressed = gzip.encode(utf8.encode(xml));

      final decoded = await _decodeAll(compressed);
      expect(decoded, contains('Canal Comprimido'));
    });

    test('.gz grande en varios chunks pequeños (simula streaming real, entrada no alineada)', () async {
      final xml =
          '<tv>${List.generate(50, (i) => '<channel id="c$i"><display-name>Canal $i</display-name></channel>').join()}</tv>';
      final compressed = gzip.encode(utf8.encode(xml));

      final chunks = <List<int>>[];
      for (var i = 0; i < compressed.length; i += 37) {
        final end = (i + 37).clamp(0, compressed.length);
        chunks.add(compressed.sublist(i, end));
      }

      final decodedChunks = await decodeXmltvBytes(
        Stream.fromIterable(chunks),
      ).toList();
      final decoded = decodedChunks.join();

      expect(decoded, contains('Canal 0'));
      expect(decoded, contains('Canal 49'));
    });
  });
}
