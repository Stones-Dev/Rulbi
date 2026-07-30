import 'dart:convert';

import 'package:iptv_protocols/src/xmltv/xmltv_core_parser.dart';
import 'package:iptv_protocols/src/xmltv/xmltv_report.dart';
import 'package:iptv_protocols/src/xmltv/xmltv_window.dart';
import 'package:test/test.dart';

final _wideWindow = XmltvWindow(from: DateTime.utc(2000), to: DateTime.utc(2100));

Stream<List<int>> _bytesOf(String xml) => Stream.value(utf8.encode(xml));

Future<XmltvImportReport> _parseReport(String xml) async {
  final builder = XmltvReportBuilder();
  await for (final event in parseXmltvCore(
    bytes: _bytesOf(xml),
    window: _wideWindow,
  )) {
    switch (event) {
      case XmltvBatch():
        break;
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
  return builder.build();
}

void main() {
  group('XmltvImportReport.toJson', () {
    // Caso real de producción (T1.3, estrés de 193 MB de epgshare01, ver
    // handoff/docs/bench/T1.3-xmltv-stress.md): el generador de
    // MUSIC.BOX.00s.musicbox emite `stop="...MM=60..."` (minuto 60, fuera
    // de rango 0-59) en vez de rodar al minuto 00 de la hora siguiente.
    // `parseXmltvDate` lo rechaza por diseño (`xmltv_date.dart`); aquí se
    // reproduce con un fragmento mínimo, no un archivo de 193 MB.
    test(
      'dialecto real MUSIC.BOX.00s.musicbox (stop con minuto 60): JSON estable',
      () async {
        final report = await _parseReport('''
<tv>
  <channel id="MUSIC.BOX.00s.musicbox"><display-name>Music Box 00s</display-name></channel>
  <programme channel="MUSIC.BOX.00s.musicbox" start="20260730050000 +0000" stop="20260730056000 +0000"><title>Programa</title></programme>
</tv>
''');

        expect(report.parsedChannels, 1);
        expect(report.parsedProgrammes, 0);
        expect(report.discardedCount, 1);
        expect(report.discarded.single.channelId, 'MUSIC.BOX.00s.musicbox');
        expect(
          report.discarded.single.reason,
          'stop ilegible: "20260730056000 +0000"',
        );

        final json = report.toJson();
        expect(json['kind'], 'xmltv');
        expect(json['parsedChannels'], 1);
        expect(json['parsedProgrammes'], 0);
        expect(json['outOfWindowProgrammes'], 0);
        expect(json['assumedUtcDates'], 0);
        expect(json['unknownChannelRefs'], <String, int>{});
        expect(json['unknownTags'], <String, int>{});
        expect(json['discardedCount'], 1);
        expect(json['discardedTruncated'], isFalse);

        final discardedJson = (json['discarded'] as List).single as Map;
        expect(discardedJson['channelId'], 'MUSIC.BOX.00s.musicbox');
        expect(
          discardedJson['reason'],
          'stop ilegible: "20260730056000 +0000"',
        );
        expect(discardedJson['entryIndex'], isA<int>());
        expect(
          discardedJson['charOffset'],
          isA<int>(),
          reason:
              'parseXmltvCore siempre pide withLocation: true — un '
              'descarte real siempre trae posición.',
        );
      },
    );

    test('round-trip toJson -> fromJson -> toJson es estable', () async {
      final report = await _parseReport('''
<tv>
  <channel id="MUSIC.BOX.00s.musicbox"><display-name>Music Box 00s</display-name></channel>
  <programme channel="MUSIC.BOX.00s.musicbox" start="20260730050000 +0000" stop="20260730056000 +0000"><title>Programa</title></programme>
</tv>
''');

      final json = report.toJson();
      final roundTripped = XmltvImportReport.fromJson(json);

      expect(roundTripped.toJson(), json);
    });

    test('discardedTruncated: true cuando se supera el cap de 1000', () async {
      final buffer = StringBuffer(
        '<tv><channel id="a"><display-name>A</display-name></channel>',
      );
      for (var i = 0; i < 1001; i++) {
        // Sin 'channel': cada una es un descarte garantizado.
        buffer.write(
          '<programme start="20260727100000 +0000" stop="20260727110000 +0000"><title>P$i</title></programme>',
        );
      }
      buffer.write('</tv>');

      final report = await _parseReport(buffer.toString());
      final json = report.toJson();

      expect(json['discardedCount'], 1001);
      expect(json['discardedTruncated'], isTrue);
      expect(json['discarded'], hasLength(1000));
    });
  });
}
