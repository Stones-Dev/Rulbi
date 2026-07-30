import 'dart:convert';

import 'package:iptv_protocols/src/xmltv/xmltv_core_parser.dart';
import 'package:iptv_protocols/src/xmltv/xmltv_entry.dart';
import 'package:iptv_protocols/src/xmltv/xmltv_window.dart';
import 'package:test/test.dart';

void main() {
  group('XmltvWindow.overlaps — casos límite (T1.3, batería 3)', () {
    final window = XmltvWindow(
      from: DateTime.utc(2026, 1, 10),
      to: DateTime.utc(2026, 1, 20),
    );

    test('programa enteramente antes de la ventana', () {
      expect(
        window.overlaps(
          start: DateTime.utc(2026, 1, 1),
          stop: DateTime.utc(2026, 1, 2),
        ),
        isFalse,
      );
    });

    test('programa enteramente después de la ventana', () {
      expect(
        window.overlaps(
          start: DateTime.utc(2026, 1, 25),
          stop: DateTime.utc(2026, 1, 26),
        ),
        isFalse,
      );
    });

    test('stop == from: justo terminó, fuera (borde excluyente)', () {
      expect(
        window.overlaps(
          start: DateTime.utc(2026, 1, 9),
          stop: DateTime.utc(2026, 1, 10),
        ),
        isFalse,
      );
    });

    test('stop un instante después de from: dentro', () {
      expect(
        window.overlaps(
          start: DateTime.utc(2026, 1, 9),
          stop: DateTime.utc(2026, 1, 10).add(const Duration(seconds: 1)),
        ),
        isTrue,
      );
    });

    test('start == to: todavía no ha llegado, fuera (borde excluyente)', () {
      expect(
        window.overlaps(
          start: DateTime.utc(2026, 1, 20),
          stop: DateTime.utc(2026, 1, 21),
        ),
        isFalse,
      );
    });

    test('start un instante antes de to: dentro', () {
      expect(
        window.overlaps(
          start: DateTime.utc(2026, 1, 20).subtract(
            const Duration(seconds: 1),
          ),
          stop: DateTime.utc(2026, 1, 21),
        ),
        isTrue,
      );
    });

    test('programa a caballo de toda la ventana (más largo que ella)', () {
      expect(
        window.overlaps(
          start: DateTime.utc(2026, 1, 1),
          stop: DateTime.utc(2026, 1, 30),
        ),
        isTrue,
      );
    });

    test('programa idéntico a la ventana', () {
      expect(
        window.overlaps(start: window.from, stop: window.to),
        isTrue,
      );
    });

    test('XmltvWindow.around(now) es [now-1d, now+7d]', () {
      final now = DateTime.utc(2026, 7, 30, 12);
      final around = XmltvWindow.around(now);
      expect(around.from, DateTime.utc(2026, 7, 29, 12));
      expect(around.to, DateTime.utc(2026, 8, 6, 12));
    });
  });

  group('filtrado por ventana en parseXmltvCore (T1.3, batería 3)', () {
    Stream<List<int>> bytesOf(String xml) => Stream.value(utf8.encode(xml));

    test('programa fuera de ventana: no se emite, solo incrementa el contador', () async {
      final window = XmltvWindow(
        from: DateTime.utc(2026, 1, 10),
        to: DateTime.utc(2026, 1, 20),
      );

      final events = await parseXmltvCore(
        bytes: bytesOf('''
<tv>
  <channel id="a"><display-name>A</display-name></channel>
  <programme channel="a" start="20260101000000 +0000" stop="20260102000000 +0000"><title>Fuera</title></programme>
  <programme channel="a" start="20260115000000 +0000" stop="20260115010000 +0000"><title>Dentro</title></programme>
</tv>
''',
        ),
        window: window,
      ).toList();

      final entries = [
        for (final e in events)
          if (e is XmltvBatch) ...e.entries,
      ];
      final programmeTitles = entries
          .whereType<XmltvProgrammeEntry>()
          .map((e) => e.programme.title);
      final summary = events.whereType<XmltvSummary>().single;

      expect(programmeTitles, ['Dentro']);
      expect(summary.outOfWindowProgrammes, 1);
      expect(summary.parsedProgrammes, 1);
    });

    test('cien programas fuera de ventana no producen ni una entrada ni un descarte', () async {
      final window = XmltvWindow(
        from: DateTime.utc(2026, 1, 10),
        to: DateTime.utc(2026, 1, 20),
      );
      final buffer = StringBuffer('<tv><channel id="a"><display-name>A</display-name></channel>');
      for (var i = 0; i < 100; i++) {
        buffer.write(
          '<programme channel="a" start="20260101000000 +0000" '
          'stop="20260101010000 +0000"><title>P$i</title></programme>',
        );
      }
      buffer.write('</tv>');

      final events = await parseXmltvCore(
        bytes: bytesOf(buffer.toString()),
        window: window,
      ).toList();

      final entries = [
        for (final e in events)
          if (e is XmltvBatch) ...e.entries,
      ];
      final programmeEntries = entries.whereType<XmltvProgrammeEntry>();
      final discards = events.whereType<XmltvCoreDiscard>();
      final summary = events.whereType<XmltvSummary>().single;

      expect(
        programmeEntries,
        isEmpty,
        reason: 'ninguno cae dentro de la ventana',
      );
      expect(
        discards,
        isEmpty,
        reason: 'fuera de ventana no es un descarte (P7)',
      );
      expect(summary.outOfWindowProgrammes, 100);
      expect(summary.parsedProgrammes, 0);
    });
  });
}
