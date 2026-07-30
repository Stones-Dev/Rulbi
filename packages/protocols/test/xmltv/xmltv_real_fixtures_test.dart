import 'dart:io';

import 'package:iptv_protocols/src/xmltv/xmltv_core_parser.dart';
import 'package:iptv_protocols/src/xmltv/xmltv_entry.dart';
import 'package:iptv_protocols/src/xmltv/xmltv_report.dart';
import 'package:iptv_protocols/src/xmltv/xmltv_window.dart';
import 'package:test/test.dart';

// Ventana fija y amplia, NO XmltvWindow.around(DateTime.now()): las
// fechas de estas fixtures reales son de finales de julio/inicios de
// agosto de 2026 (verificado: epg_pw_lite 28/07–04/08, epgshare01_es1
// 27/07–01/08). Con la ventana de producción [now-1d, now+7d], pasado
// ese rango el resultado correcto sería 0 programas — este test dejaría
// de decir nada útil en cuanto caduque. Una ventana fija que cubre todo
// el rango real hace el smoke test estable en el tiempo.
final _fixedWindow = XmltvWindow(
  from: DateTime.utc(2026, 7, 20),
  to: DateTime.utc(2026, 8, 10),
);

const _dir = 'test/fixtures/xmltv';

final class _ParsedFixture {
  _ParsedFixture(this.entries, this.report);
  final List<XmltvEntry> entries;
  final XmltvImportReport report;
}

Future<_ParsedFixture> _parseFile(String path) async {
  final builder = XmltvReportBuilder();
  final collected = <XmltvEntry>[];
  await for (final event in parseXmltvCore(
    bytes: File(path).openRead(),
    window: _fixedWindow,
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
  return _ParsedFixture(collected, builder.build());
}

void main() {
  group('parseXmltvCore — smoke test sobre fixtures reales (T1.1 xmltv/)', () {
    test('epg_pw_lite.xml.gz: 357 canales, 54586 programas, sin descartes', () async {
      final result = await _parseFile('$_dir/epg_pw_lite.xml.gz');

      expect(result.report.parsedChannels, 357);
      expect(result.report.parsedProgrammes, 54586);
      expect(result.report.outOfWindowProgrammes, 0);
      expect(result.report.discardedCount, 0);
      expect(result.report.discarded, isEmpty);
      expect(
        result.report.unknownChannelRefs,
        isEmpty,
        reason: 'todo <programme channel="..."> referencia un <channel> real',
      );
      expect(
        result.report.assumedUtcDates,
        0,
        reason: 'todas las fechas de esta fixture traen offset',
      );

      final channels = result.entries.whereType<XmltvChannelEntry>();
      expect(channels, hasLength(357));
      expect(
        channels.every((e) => e.channel.displayNames.isNotEmpty),
        isTrue,
      );
    });

    test('epgshare01_es1.xml.gz: 373 canales, 33621 programas, sin descartes', () async {
      final result = await _parseFile('$_dir/epgshare01_es1.xml.gz');

      expect(result.report.parsedChannels, 373);
      expect(result.report.parsedProgrammes, 33621);
      expect(result.report.outOfWindowProgrammes, 0);
      expect(result.report.discardedCount, 0);
      expect(result.report.discarded, isEmpty);
      expect(result.report.unknownChannelRefs, isEmpty);
      expect(result.report.assumedUtcDates, 0);

      final channels = result.entries.whereType<XmltvChannelEntry>();
      expect(channels, hasLength(373));
      // '#Vamos.es' del README de T1.1: verifica que el id de canal se
      // conserva crudo (incluido el '#'), sin normalizar — es la clave de
      // join con Channel.tvgId, que tampoco se normaliza.
      expect(channels.any((e) => e.channel.id == '#Vamos.es'), isTrue);

      final programmes = result.entries.whereType<XmltvProgrammeEntry>();
      expect(
        programmes.every((e) => e.programme.title.isNotEmpty),
        isTrue,
        reason: 'ninguna entrada real de esta fixture carece de <title>',
      );
    });
  });
}
