import 'package:iptv_protocols/src/xmltv/xmltv_entry.dart';
import 'package:iptv_protocols/src/xmltv/xmltv_window.dart';
import 'package:iptv_protocols/src/xtream/xtream_epg.dart';
import 'package:iptv_protocols/src/xtream/xtream_epg_adapter.dart';
import 'package:test/test.dart';

/// `xtreamEpgToEntries` (S5.5, Bloque A3) — adapta `XtreamEpgListing` (por
/// canal, `get_short_epg`/`get_simple_data_table`) al lenguaje de entrada
/// del escritor de ADR-008 (`XmltvEntry`/`EpgProgramme`), fallback bajo
/// demanda cuando un panel no sirve `xmltv.php` (ver Bloque A1/A2). El
/// escritor (`DriftXmltvEpgWriter`) no se toca ni se generaliza — esta
/// función solo produce lo que él ya sabe consumir.
void main() {
  final window = XmltvWindow(
    from: DateTime.utc(2026, 7, 31, 0),
    to: DateTime.utc(2026, 8, 7, 0),
  );

  group('conversión directa', () {
    test('una entrada con start/end dentro de ventana se convierte a XmltvProgrammeEntry', () {
      final listings = [
        XtreamEpgListing(
          id: '1',
          title: 'Telediario 21h',
          description: 'Resumen de la actualidad.',
          start: DateTime.utc(2026, 7, 31, 21),
          end: DateTime.utc(2026, 7, 31, 22),
        ),
      ];

      final entries = xtreamEpgToEntries(tvgId: 'canal.1', listings: listings, window: window).toList();

      expect(entries, hasLength(1));
      final entry = entries.single as XmltvProgrammeEntry;
      expect(entry.programme.tvgId, 'canal.1');
      expect(entry.programme.title, 'Telediario 21h');
      expect(entry.programme.description, 'Resumen de la actualidad.');
      expect(entry.programme.start, DateTime.utc(2026, 7, 31, 21));
      expect(entry.programme.stop, DateTime.utc(2026, 7, 31, 22));
    });

    test('start local (vía texto) se normaliza a UTC igual que epoch', () {
      // _parseTimestamp de xtream_epg.dart produce DateTime LOCAL por la
      // vía de texto ("YYYY-MM-DD HH:mm:ss") y UTC por la vía de epoch —
      // el adaptador debe normalizar ambas a UTC antes de construir
      // EpgProgramme, para que _programmeKey (writer, .toUtc()) y la
      // ventana comparen instantes reales, no wall-clock local.
      final localStart = DateTime.parse('2026-08-01T10:00:00'); // local
      final localEnd = DateTime.parse('2026-08-01T11:00:00'); // local
      final listings = [
        XtreamEpgListing(id: '1', title: 'Programa', start: localStart, end: localEnd),
      ];

      final entries = xtreamEpgToEntries(tvgId: 'canal.1', listings: listings, window: window).toList();

      final entry = entries.single as XmltvProgrammeEntry;
      expect(entry.programme.start.isUtc, isTrue);
      expect(entry.programme.stop.isUtc, isTrue);
      expect(entry.programme.start.isAtSameMomentAs(localStart), isTrue);
      expect(entry.programme.stop.isAtSameMomentAs(localEnd), isTrue);
    });

    test('varias entradas producen varias XmltvProgrammeEntry, en el mismo orden', () {
      final listings = [
        XtreamEpgListing(
          id: '1',
          title: 'A',
          start: DateTime.utc(2026, 7, 31, 20),
          end: DateTime.utc(2026, 7, 31, 21),
        ),
        XtreamEpgListing(
          id: '2',
          title: 'B',
          start: DateTime.utc(2026, 7, 31, 21),
          end: DateTime.utc(2026, 7, 31, 22),
        ),
      ];

      final entries = xtreamEpgToEntries(tvgId: 'canal.1', listings: listings, window: window).toList();

      expect(entries, hasLength(2));
      expect((entries[0] as XmltvProgrammeEntry).programme.title, 'A');
      expect((entries[1] as XmltvProgrammeEntry).programme.title, 'B');
    });
  });

  group('descarte (análogo a XmltvDiscard)', () {
    test('start null se descarta', () {
      final listings = [
        XtreamEpgListing(id: '1', title: 'Sin start', end: DateTime.utc(2026, 8, 1, 10)),
      ];

      expect(xtreamEpgToEntries(tvgId: 'canal.1', listings: listings, window: window), isEmpty);
    });

    test('end null se descarta', () {
      final listings = [
        XtreamEpgListing(id: '1', title: 'Sin end', start: DateTime.utc(2026, 8, 1, 10)),
      ];

      expect(xtreamEpgToEntries(tvgId: 'canal.1', listings: listings, window: window), isEmpty);
    });

    test('end <= start se descarta (rango degenerado o invertido)', () {
      final listings = [
        XtreamEpgListing(
          id: '1',
          title: 'Invertido',
          start: DateTime.utc(2026, 8, 1, 10),
          end: DateTime.utc(2026, 8, 1, 9),
        ),
        XtreamEpgListing(
          id: '2',
          title: 'Degenerado',
          start: DateTime.utc(2026, 8, 1, 10),
          end: DateTime.utc(2026, 8, 1, 10),
        ),
      ];

      expect(xtreamEpgToEntries(tvgId: 'canal.1', listings: listings, window: window), isEmpty);
    });

    test('fuera de la ventana (antes de from) se descarta', () {
      final listings = [
        XtreamEpgListing(
          id: '1',
          title: 'Muy pasado',
          start: DateTime.utc(2026, 7, 20, 10),
          end: DateTime.utc(2026, 7, 20, 11),
        ),
      ];

      expect(xtreamEpgToEntries(tvgId: 'canal.1', listings: listings, window: window), isEmpty);
    });

    test('fuera de la ventana (después de to) se descarta', () {
      final listings = [
        XtreamEpgListing(
          id: '1',
          title: 'Muy futuro',
          start: DateTime.utc(2026, 9, 1, 10),
          end: DateTime.utc(2026, 9, 1, 11),
        ),
      ];

      expect(xtreamEpgToEntries(tvgId: 'canal.1', listings: listings, window: window), isEmpty);
    });

    test('una entrada válida sobrevive junto a varias descartadas', () {
      final listings = [
        XtreamEpgListing(id: '1', title: 'Sin start', end: DateTime.utc(2026, 8, 1, 10)),
        XtreamEpgListing(
          id: '2',
          title: 'Válida',
          start: DateTime.utc(2026, 8, 1, 10),
          end: DateTime.utc(2026, 8, 1, 11),
        ),
        XtreamEpgListing(
          id: '3',
          title: 'Muy futuro',
          start: DateTime.utc(2026, 9, 1, 10),
          end: DateTime.utc(2026, 9, 1, 11),
        ),
      ];

      final entries = xtreamEpgToEntries(tvgId: 'canal.1', listings: listings, window: window).toList();

      expect(entries, hasLength(1));
      expect((entries.single as XmltvProgrammeEntry).programme.title, 'Válida');
    });
  });
}
