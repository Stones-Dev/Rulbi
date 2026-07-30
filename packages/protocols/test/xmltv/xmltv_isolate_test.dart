import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:iptv_protocols/src/xmltv/xmltv_entry.dart';
import 'package:iptv_protocols/src/xmltv/xmltv_parser.dart';
import 'package:iptv_protocols/src/xmltv/xmltv_window.dart';
import 'package:test/test.dart';

final _wideWindow = XmltvWindow(
  from: DateTime.utc(2000),
  to: DateTime.utc(2100),
);

const _sampleXml = '''
<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <channel id="a"><display-name>Canal A</display-name></channel>
  <programme channel="a" start="20260727100000 +0000" stop="20260727110000 +0000">
    <title>Programa</title>
  </programme>
</tv>
''';

void main() {
  group('parseXmltv — wrapper público con isolate real (T1.3, batería 7)', () {
    test('onListen diferido: no consume bytes si nadie escucha entries', () async {
      var listened = false;
      final controller = StreamController<List<int>>();
      final bytes = controller.stream.map((chunk) {
        listened = true;
        return chunk;
      });

      parseXmltv(bytes: bytes, window: _wideWindow);
      // Sin escuchar `entries`: se le da tiempo a que, si fuera a
      // spawnear el isolate y bombear bytes, ya lo hubiera hecho.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(listened, isFalse);
      // Nadie escuchó nunca `controller.stream`, así que su future de
      // cierre no tiene por qué completar — no se espera.
      unawaited(controller.close());
    });

    test('parsea un XMLTV real de extremo a extremo a través del isolate', () async {
      final outcome = parseXmltv(
        bytes: Stream.value(utf8.encode(_sampleXml)),
        window: _wideWindow,
      );

      final entries = await outcome.entries.toList();
      final report = await outcome.report;

      expect(entries.whereType<XmltvChannelEntry>(), hasLength(1));
      expect(entries.whereType<XmltvProgrammeEntry>(), hasLength(1));
      expect(report.parsedChannels, 1);
      expect(report.parsedProgrammes, 1);
      expect(report.discardedCount, 0);

      final channel =
          entries.whereType<XmltvChannelEntry>().single.channel;
      expect(channel.id, 'a');
      final programme =
          entries.whereType<XmltvProgrammeEntry>().single.programme;
      expect(programme.title, 'Programa');
    });

    test('un .gz real llega decodificado a través de la API pública con isolate', () async {
      final compressed = gzip.encode(utf8.encode(_sampleXml));
      final outcome = parseXmltv(
        bytes: Stream.value(compressed),
        window: _wideWindow,
      );

      final entries = await outcome.entries.toList();
      final report = await outcome.report;

      expect(entries.whereType<XmltvChannelEntry>(), hasLength(1));
      expect(report.parsedProgrammes, 1);
    });

    test('un error del stream de bytes de entrada llega como error del stream de salida, no como descarte', () async {
      final controller = StreamController<List<int>>();
      final outcome = parseXmltv(
        bytes: controller.stream,
        window: _wideWindow,
      );

      final entriesFuture = outcome.entries.toList();
      // Deja que el isolate arranque y se ponga a escuchar antes de
      // fallar el stream de entrada.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      controller.addError(StateError('fallo simulado de lectura'));
      await controller.close();

      await expectLater(entriesFuture, throwsA(isA<StateError>()));
      await expectLater(outcome.report, throwsA(isA<StateError>()));
    });

    test('lotes grandes se entrelazan igual que en el núcleo sin isolate', () async {
      final buffer = StringBuffer('<tv>');
      for (var i = 0; i < 5; i++) {
        buffer.write(
          '<channel id="c$i"><display-name>C$i</display-name></channel>'
          '<programme channel="c$i" start="20260727100000 +0000" '
          'stop="20260727110000 +0000"><title>P$i</title></programme>',
        );
      }
      buffer.write('</tv>');

      final outcome = parseXmltv(
        bytes: Stream.value(utf8.encode(buffer.toString())),
        window: _wideWindow,
        batchSize: 3,
      );
      final entries = await outcome.entries.toList();
      final report = await outcome.report;

      expect(entries, hasLength(10)); // 5 canales + 5 programas
      expect(report.parsedChannels, 5);
      expect(report.parsedProgrammes, 5);
      // Orden entrelazado del documento, no agrupado por tipo.
      expect(entries.first, isA<XmltvChannelEntry>());
      expect(entries[1], isA<XmltvProgrammeEntry>());
    });
  });
}
