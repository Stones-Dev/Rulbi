import 'dart:convert';

import 'package:iptv_protocols/src/xmltv/xmltv_core_parser.dart';
import 'package:iptv_protocols/src/xmltv/xmltv_entry.dart';
import 'package:iptv_protocols/src/xmltv/xmltv_window.dart';
import 'package:test/test.dart';

final _wideWindow = XmltvWindow(
  from: DateTime.utc(2000),
  to: DateTime.utc(2100),
);

Stream<List<int>> _bytesOf(String xml) => Stream.value(utf8.encode(xml));

Future<List<XmltvCoreEvent>> _drain(String xml) =>
    parseXmltvCore(bytes: _bytesOf(xml), window: _wideWindow).toList();

List<XmltvEntry> _entriesOf(List<XmltvCoreEvent> events) => [
  for (final event in events)
    if (event is XmltvBatch) ...event.entries,
];

void main() {
  group('parseXmltvCore — documentos malformados/truncados (T1.3, batería 6)', () {
    test(
      'truncado a media etiqueta abierta (simula gunzip roto / descarga cortada): '
      'no lanza, conserva lo ya emitido, reporta un descarte final',
      () async {
        // El primer canal cierra bien; el segundo se corta a media
        // apertura de <display-na — ni siquiera el nombre del atributo
        // llega a completarse, no hay forma de que el tokenizer termine
        // ese token limpiamente.
        const truncated =
            '<tv>'
            '<channel id="a"><display-name>Canal A</display-name></channel>'
            '<channel id="b"><display-na';

        // Si esto lanzara, el propio `await` haría fallar el test con una
        // excepción no capturada — la ausencia de ese fallo ya demuestra
        // que parseXmltvCore no relanza (P7).
        final events = await _drain(truncated);

        final channels = _entriesOf(
          events,
        ).whereType<XmltvChannelEntry>().toList();
        expect(
          channels,
          hasLength(1),
          reason: 'el canal A, completo antes del corte, se conserva',
        );
        expect(channels.single.channel.id, 'a');

        final discards = events.whereType<XmltvCoreDiscard>();
        expect(
          discards,
          isNotEmpty,
          reason: 'el corte se reporta, no desaparece en silencio (P7)',
        );
      },
    );

    test('<tv> nunca se cierra: no lanza, el contenido ya visto se conserva', () async {
      const noClosingTv =
          '<tv>'
          '<channel id="a"><display-name>Canal A</display-name></channel>'
          '<programme channel="a" start="20260727100000 +0000" stop="20260727110000 +0000">'
          '<title>Programa</title></programme>';
      // Nótese: sin </tv> final.

      final events = await _drain(noClosingTv);
      final entries = _entriesOf(events);

      expect(entries.whereType<XmltvChannelEntry>(), hasLength(1));
      expect(entries.whereType<XmltvProgrammeEntry>(), hasLength(1));
    });

    test('basura de texto antes de la declaración/<?xml?>: se ignora, el resto se parsea', () async {
      const garbagePrefix =
          'esto no es XML en absoluto\n'
          '<?xml version="1.0" encoding="UTF-8"?>'
          '<tv><channel id="a"><display-name>Canal A</display-name></channel></tv>';

      final events = await _drain(garbagePrefix);
      final channels = _entriesOf(
        events,
      ).whereType<XmltvChannelEntry>().toList();

      expect(channels, hasLength(1));
      expect(channels.single.channel.id, 'a');
    });

    test('documento completamente vacío: no lanza, no produce entradas, resumen en ceros', () async {
      final events = await _drain('');

      expect(_entriesOf(events), isEmpty);
      final summary = events.whereType<XmltvSummary>().single;
      expect(summary.parsedChannels, 0);
      expect(summary.parsedProgrammes, 0);
      expect(summary.outOfWindowProgrammes, 0);
    });

    test(
      '</programme> huérfano (sin apertura correspondiente) no desincroniza '
      'el resto del árbol: el canal siguiente se parsea igual',
      () async {
        const orphanClose =
            '<tv>'
            '<channel id="a"><display-name>A</display-name></channel>'
            '</programme>' // huérfano: no hay <programme> abierto aquí
            '<channel id="b"><display-name>B</display-name></channel>'
            '</tv>';

        final events = await _drain(orphanClose);
        final channels = _entriesOf(
          events,
        ).whereType<XmltvChannelEntry>().map((e) => e.channel.id).toList();

        expect(
          channels,
          ['a', 'b'],
          reason:
              'el cierre huérfano se ignora sin popear nada — si '
              'desincronizara la pila, "b" se perdería o se malinterpretaría',
        );
      },
    );
  });
}
