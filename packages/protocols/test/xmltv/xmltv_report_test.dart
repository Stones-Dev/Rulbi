import 'dart:convert';

import 'package:iptv_protocols/src/xmltv/xmltv_core_parser.dart';
import 'package:iptv_protocols/src/xmltv/xmltv_entry.dart';
import 'package:iptv_protocols/src/xmltv/xmltv_report.dart';
import 'package:iptv_protocols/src/xmltv/xmltv_window.dart';
import 'package:test/test.dart';

final _wideWindow = XmltvWindow(
  from: DateTime.utc(2000),
  to: DateTime.utc(2100),
);

Stream<List<int>> _bytesOf(String xml) => Stream.value(utf8.encode(xml));

final class _Result {
  _Result(this.entries, this.report);
  final List<XmltvEntry> entries;
  final XmltvImportReport report;
}

Future<_Result> _parse(String xml, {XmltvWindow? window}) async {
  final builder = XmltvReportBuilder();
  final collected = <XmltvEntry>[];
  await for (final event in parseXmltvCore(
    bytes: _bytesOf(xml),
    window: window ?? _wideWindow,
  )) {
    switch (event) {
      case XmltvBatch(:final entries):
        collected.addAll(entries);
      case XmltvCoreDiscard(:final discard):
        builder.addDiscard(discard);
      case XmltvSummary(
        :final parsedChannels,
        :final parsedProgrammes,
        :final outOfWindowProgrammes,
        :final assumedUtcDates,
        :final unknownChannelRefs,
        :final unknownTags,
      ):
        builder.applySummary(
          parsedChannels: parsedChannels,
          parsedProgrammes: parsedProgrammes,
          outOfWindowProgrammes: outOfWindowProgrammes,
          assumedUtcDates: assumedUtcDates,
          unknownChannelRefs: unknownChannelRefs,
          unknownTags: unknownTags,
        );
    }
  }
  return _Result(collected, builder.build());
}

void main() {
  group('XmltvImportReport — política de tolerancia (T1.3, batería 4)', () {
    test('<programme> sin atributo channel: descarte con motivo', () async {
      final result = await _parse('''
<tv>
  <channel id="a"><display-name>A</display-name></channel>
  <programme start="20260727100000 +0000" stop="20260727110000 +0000"><title>Huérfano</title></programme>
</tv>
''');

      expect(result.entries.whereType<XmltvProgrammeEntry>(), isEmpty);
      expect(result.report.discardedCount, 1);
      expect(result.report.discarded.single.reason, contains('channel'));
    });

    test('start ausente: descarte con motivo', () async {
      final result = await _parse('''
<tv>
  <channel id="a"><display-name>A</display-name></channel>
  <programme channel="a" stop="20260727110000 +0000"><title>Sin start</title></programme>
</tv>
''');

      expect(result.entries.whereType<XmltvProgrammeEntry>(), isEmpty);
      expect(result.report.discardedCount, 1);
      expect(result.report.discarded.single.reason, contains('start'));
      expect(result.report.discarded.single.channelId, 'a');
    });

    test('start ilegible (basura): descarte con motivo', () async {
      final result = await _parse('''
<tv>
  <channel id="a"><display-name>A</display-name></channel>
  <programme channel="a" start="no-es-una-fecha" stop="20260727110000 +0000"><title>X</title></programme>
</tv>
''');

      expect(result.entries.whereType<XmltvProgrammeEntry>(), isEmpty);
      expect(result.report.discardedCount, 1);
      expect(result.report.discarded.single.reason, contains('start'));
    });

    test('stop ausente: descarte con motivo', () async {
      final result = await _parse('''
<tv>
  <channel id="a"><display-name>A</display-name></channel>
  <programme channel="a" start="20260727100000 +0000"><title>Sin stop</title></programme>
</tv>
''');

      expect(result.entries.whereType<XmltvProgrammeEntry>(), isEmpty);
      expect(result.report.discardedCount, 1);
      expect(result.report.discarded.single.reason, contains('stop'));
    });

    test('stop ilegible (basura): descarte con motivo', () async {
      final result = await _parse('''
<tv>
  <channel id="a"><display-name>A</display-name></channel>
  <programme channel="a" start="20260727100000 +0000" stop="basura"><title>X</title></programme>
</tv>
''');

      expect(result.entries.whereType<XmltvProgrammeEntry>(), isEmpty);
      expect(result.report.discardedCount, 1);
      expect(result.report.discarded.single.reason, contains('stop'));
    });

    test('fecha sin offset horario: se emite igual, se cuenta assumedUtcDates', () async {
      final result = await _parse('''
<tv>
  <channel id="a"><display-name>A</display-name></channel>
  <programme channel="a" start="20260727100000" stop="20260727110000"><title>Sin offset</title></programme>
</tv>
''');

      expect(result.entries.whereType<XmltvProgrammeEntry>(), hasLength(1));
      expect(result.report.discardedCount, 0);
      expect(result.report.assumedUtcDates, 1);
    });

    test('referencia a canal no declarado: se emite igual, se cuenta en unknownChannelRefs', () async {
      final result = await _parse('''
<tv>
  <programme channel="fantasma" start="20260727100000 +0000" stop="20260727110000 +0000"><title>X</title></programme>
</tv>
''');

      expect(result.entries.whereType<XmltvProgrammeEntry>(), hasLength(1));
      expect(result.report.discardedCount, 0);
      expect(result.report.unknownChannelRefs, {'fantasma': 1});
    });

    test(
      'canal declarado DESPUÉS de sus programas (no conforme al DTD, tolerado): '
      'no cuenta como ref desconocida al reconciliar al cierre',
      () async {
        final result = await _parse('''
<tv>
  <programme channel="a" start="20260727100000 +0000" stop="20260727110000 +0000"><title>X</title></programme>
  <channel id="a"><display-name>A</display-name></channel>
</tv>
''');

        expect(result.report.unknownChannelRefs, isEmpty);
      },
    );

    test('etiqueta desconocida bajo <tv>: se ignora el subárbol, se cuenta en unknownTags', () async {
      final result = await _parse('''
<tv>
  <some-vendor-extension><nested>x</nested></some-vendor-extension>
  <channel id="a"><display-name>A</display-name></channel>
</tv>
''');

      expect(result.report.unknownTags, {'some-vendor-extension': 1});
      expect(
        result.report.unknownTags.containsKey('nested'),
        isFalse,
        reason:
            'un hijo anidado dentro de un subárbol ya descartado no se '
            'cuenta aparte (memoria acotada frente a <credits><actor/>×N)',
      );
    });

    test('etiqueta desconocida bajo <programme> (p. ej. <category>): se cuenta, el programa se conserva', () async {
      final result = await _parse('''
<tv>
  <channel id="a"><display-name>A</display-name></channel>
  <programme channel="a" start="20260727100000 +0000" stop="20260727110000 +0000">
    <title>X</title>
    <category>Deportes</category>
    <credits><actor>Alguien</actor><director>Alguien Más</director></credits>
  </programme>
</tv>
''');

      expect(result.entries.whereType<XmltvProgrammeEntry>(), hasLength(1));
      expect(result.report.unknownTags['category'], 1);
      expect(result.report.unknownTags['credits'], 1);
      expect(
        result.report.unknownTags.containsKey('actor'),
        isFalse,
        reason: 'anidado dentro de <credits>, ya descartado',
      );
    });

    test('<channel> sin atributo id: descarte con motivo', () async {
      final result = await _parse('''
<tv>
  <channel><display-name>Sin id</display-name></channel>
</tv>
''');

      expect(result.entries.whereType<XmltvChannelEntry>(), isEmpty);
      expect(result.report.discardedCount, 1);
      expect(result.report.discarded.single.reason, contains('id'));
    });

    test('cap de descartes: 1001 entradas rotas → lista de 1000, discardedTruncated', () async {
      final buffer = StringBuffer('<tv><channel id="a"><display-name>A</display-name></channel>');
      for (var i = 0; i < 1001; i++) {
        // Sin 'channel': cada una es un descarte garantizado.
        buffer.write(
          '<programme start="20260727100000 +0000" stop="20260727110000 +0000"><title>P$i</title></programme>',
        );
      }
      buffer.write('</tv>');

      final result = await _parse(buffer.toString());

      expect(result.report.discardedCount, 1001);
      expect(result.report.discarded, hasLength(1000));
      expect(result.report.discardedTruncated, isTrue);
    });

    test('sin descartes: discardedTruncated es false y la lista está vacía', () async {
      final result = await _parse('''
<tv>
  <channel id="a"><display-name>A</display-name></channel>
  <programme channel="a" start="20260727100000 +0000" stop="20260727110000 +0000"><title>OK</title></programme>
</tv>
''');

      expect(result.report.discardedCount, 0);
      expect(result.report.discarded, isEmpty);
      expect(result.report.discardedTruncated, isFalse);
    });
  });
}
