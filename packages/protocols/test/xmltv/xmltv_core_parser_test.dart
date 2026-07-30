import 'dart:convert';

import 'package:iptv_protocols/src/xmltv/xmltv_core_parser.dart';
import 'package:iptv_protocols/src/xmltv/xmltv_entry.dart';
import 'package:iptv_protocols/src/xmltv/xmltv_window.dart';
import 'package:test/test.dart';

/// Ventana deliberadamente enorme: esta batería testea el estado del
/// núcleo SAX (canales/programas/lotes/entidades/CDATA), no el filtrado
/// por ventana temporal (eso es la batería 3, xmltv_window_test.dart).
final _wideWindow = XmltvWindow(
  from: DateTime.utc(2000),
  to: DateTime.utc(2100),
);

Stream<List<int>> _bytesOf(String xml) => Stream.value(utf8.encode(xml));

Future<List<XmltvCoreEvent>> _drain(
  String xml, {
  XmltvWindow? window,
  int batchSize = 500,
}) => parseXmltvCore(
  bytes: _bytesOf(xml),
  window: window ?? _wideWindow,
  batchSize: batchSize,
).toList();

List<XmltvEntry> _entriesOf(List<XmltvCoreEvent> events) => [
  for (final event in events)
    if (event is XmltvBatch) ...event.entries,
];

XmltvSummary _summaryOf(List<XmltvCoreEvent> events) =>
    events.whereType<XmltvSummary>().single;

void main() {
  group('parseXmltvCore — núcleo SAX (T1.3, batería 2)', () {
    test('documento mínimo válido: un canal, un programa', () async {
      final events = await _drain('''
<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <channel id="canal1.es">
    <display-name>Canal Uno</display-name>
  </channel>
  <programme channel="canal1.es" start="20260727100000 +0000" stop="20260727110000 +0000">
    <title>Programa A</title>
  </programme>
</tv>
''');

      final entries = _entriesOf(events);
      expect(entries, hasLength(2));

      final channelEntry = entries[0] as XmltvChannelEntry;
      expect(channelEntry.channel.id, 'canal1.es');
      expect(channelEntry.channel.displayNames, ['Canal Uno']);

      final programmeEntry = entries[1] as XmltvProgrammeEntry;
      expect(programmeEntry.programme.tvgId, 'canal1.es');
      expect(programmeEntry.programme.title, 'Programa A');
      expect(
        programmeEntry.programme.start,
        DateTime.utc(2026, 7, 27, 10, 0, 0),
      );
      expect(
        programmeEntry.programme.stop,
        DateTime.utc(2026, 7, 27, 11, 0, 0),
      );

      final summary = _summaryOf(events);
      expect(summary.parsedChannels, 1);
      expect(summary.parsedProgrammes, 1);
      expect(summary.unknownChannelRefs, isEmpty);
      expect(summary.unknownTags, isEmpty);
    });

    test('entrelaza canales y programas en el orden del documento, no agrupados por tipo', () async {
      final events = await _drain('''
<tv>
  <channel id="a"><display-name>A</display-name></channel>
  <programme channel="a" start="20260727100000 +0000" stop="20260727110000 +0000"><title>P1</title></programme>
  <channel id="b"><display-name>B</display-name></channel>
  <programme channel="b" start="20260727100000 +0000" stop="20260727110000 +0000"><title>P2</title></programme>
</tv>
''');

      final entries = _entriesOf(events);
      expect(entries, hasLength(4));
      expect(entries[0], isA<XmltvChannelEntry>());
      expect(entries[1], isA<XmltvProgrammeEntry>());
      expect(entries[2], isA<XmltvChannelEntry>());
      expect(entries[3], isA<XmltvProgrammeEntry>());
    });

    test('respeta batchSize: N canales producen ceil(N/batchSize) lotes', () async {
      final buffer = StringBuffer('<tv>');
      for (var i = 0; i < 7; i++) {
        buffer.write('<channel id="c$i"><display-name>C$i</display-name></channel>');
      }
      buffer.write('</tv>');

      final events = await _drain(buffer.toString(), batchSize: 3);
      final batches = events.whereType<XmltvBatch>().toList();

      expect(batches, hasLength(3)); // 3 + 3 + 1
      expect(batches[0].entries, hasLength(3));
      expect(batches[1].entries, hasLength(3));
      expect(batches[2].entries, hasLength(1));
    });

    test('<icon/> self-closing en un canal', () async {
      final events = await _drain('''
<tv>
  <channel id="a">
    <display-name>A</display-name>
    <icon src="https://example.com/logo.png" />
  </channel>
</tv>
''');

      final channel = (_entriesOf(events).single as XmltvChannelEntry).channel;
      expect(channel.icon, Uri.parse('https://example.com/logo.png'));
    });

    test('varios <display-name> se conservan todos, en orden', () async {
      final events = await _drain('''
<tv>
  <channel id="a">
    <display-name lang="es">Canal Uno</display-name>
    <display-name lang="en">Channel One</display-name>
  </channel>
</tv>
''');

      final channel = (_entriesOf(events).single as XmltvChannelEntry).channel;
      expect(channel.displayNames, ['Canal Uno', 'Channel One']);
    });

    test('<url> de canal se conserva como Uri', () async {
      final events = await _drain('''
<tv>
  <channel id="a">
    <display-name>A</display-name>
    <url>http://example.com</url>
  </channel>
</tv>
''');

      final channel = (_entriesOf(events).single as XmltvChannelEntry).channel;
      expect(channel.urls, [Uri.parse('http://example.com')]);
    });

    test('entidades XML estándar se decodifican en título y descripción', () async {
      final events = await _drain('''
<tv>
  <channel id="a"><display-name>A</display-name></channel>
  <programme channel="a" start="20260727100000 +0000" stop="20260727110000 +0000">
    <title>Tom &amp; Jerry</title>
    <desc>&lt;Serie&gt; con &quot;comillas&quot;</desc>
  </programme>
</tv>
''');

      final programme =
          (_entriesOf(events).last as XmltvProgrammeEntry).programme;
      expect(programme.title, 'Tom & Jerry');
      expect(programme.description, '<Serie> con "comillas"');
    });

    test('CDATA en <desc> se conserva literal', () async {
      final events = await _drain('''
<tv>
  <channel id="a"><display-name>A</display-name></channel>
  <programme channel="a" start="20260727100000 +0000" stop="20260727110000 +0000">
    <title>P</title>
    <desc><![CDATA[Texto <con> caracteres & especiales]]></desc>
  </programme>
</tv>
''');

      final programme =
          (_entriesOf(events).last as XmltvProgrammeEntry).programme;
      expect(programme.description, 'Texto <con> caracteres & especiales');
    });

    test('<title> duplicado: gana el primero', () async {
      final events = await _drain('''
<tv>
  <channel id="a"><display-name>A</display-name></channel>
  <programme channel="a" start="20260727100000 +0000" stop="20260727110000 +0000">
    <title lang="es">Título en español</title>
    <title lang="en">Title in English</title>
  </programme>
</tv>
''');

      final programme =
          (_entriesOf(events).last as XmltvProgrammeEntry).programme;
      expect(programme.title, 'Título en español');
    });

    test('programa sin <title>: se conserva con título vacío, no se descarta', () async {
      final events = await _drain('''
<tv>
  <channel id="a"><display-name>A</display-name></channel>
  <programme channel="a" start="20260727100000 +0000" stop="20260727110000 +0000" />
</tv>
''');

      final entries = _entriesOf(events);
      expect(entries, hasLength(2));
      final programme = (entries.last as XmltvProgrammeEntry).programme;
      expect(programme.title, '');
      expect(events.whereType<XmltvCoreDiscard>(), isEmpty);
    });

    test('<programme> autocerrado sin título ni descripción (self-closing)', () async {
      final events = await _drain('''
<tv>
  <channel id="a"><display-name>A</display-name></channel>
  <programme channel="a" start="20260727100000 +0000" stop="20260727110000 +0000"></programme>
</tv>
''');

      expect(_entriesOf(events), hasLength(2));
    });
  });
}
