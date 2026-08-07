import 'package:iptv_protocols/src/xtream/xtream_import_report.dart';
import 'package:test/test.dart';

/// T1.9 extendido a Xtream (T1.4): mismo criterio de estabilidad que
/// `ImportReport` (M3U) y `XmltvImportReport` (XMLTV) — claves en orden
/// fijo, no dependen de `hashCode` de ningún `Map` interno de Dart.
/// `kind: 'xtream'` es el tercer discriminador del sobre compuesto
/// (`docs/import-report-schema.md`).
void main() {
  group('XtreamImportReport — serialización JSON estable', () {
    test('toJson produce el discriminador kind:xtream y las claves esperadas', () {
      const report = XtreamImportReport(
        parsedLive: 2,
        parsedVod: 1,
        parsedSeries: 1,
        discardedCount: 1,
        discarded: [XtreamDiscard(action: 'get_vod_streams', reason: 'XtreamHttpFailure(500)')],
      );

      final json = report.toJson();

      expect(json['kind'], 'xtream');
      expect(json['parsedLive'], 2);
      expect(json['parsedVod'], 1);
      expect(json['parsedSeries'], 1);
      expect(json['discardedCount'], 1);
      expect(json['discarded'], [
        {'action': 'get_vod_streams', 'reason': 'XtreamHttpFailure(500)'},
      ]);
    });

    test('fromJson(toJson(x)) reconstruye un reporte equivalente', () {
      const original = XtreamImportReport(
        parsedLive: 26752,
        parsedVod: 0,
        parsedSeries: 340,
        discardedCount: 2,
        discarded: [
          XtreamDiscard(action: 'get_live_categories', reason: 'XtreamRateLimited(retryAfter: null)'),
          XtreamDiscard(action: 'get_vod_streams', reason: 'XtreamNetworkFailure(timeout)'),
        ],
      );

      final roundTripped = XtreamImportReport.fromJson(original.toJson());

      expect(roundTripped.parsedLive, original.parsedLive);
      expect(roundTripped.parsedVod, original.parsedVod);
      expect(roundTripped.parsedSeries, original.parsedSeries);
      expect(roundTripped.discardedCount, original.discardedCount);
      expect(roundTripped.discarded.map((d) => d.action), original.discarded.map((d) => d.action));
      expect(roundTripped.discarded.map((d) => d.reason), original.discarded.map((d) => d.reason));
    });

    test('el mismo reporte produce siempre el mismo JSON (estabilidad entre corridas)', () {
      const report = XtreamImportReport(
        parsedLive: 5,
        parsedVod: 3,
        parsedSeries: 2,
        discardedCount: 0,
        discarded: [],
      );

      expect(report.toJson(), report.toJson());
    });

    test('sin descartes: discarded es una lista vacía, no null', () {
      const report = XtreamImportReport(
        parsedLive: 1,
        parsedVod: 0,
        parsedSeries: 0,
        discardedCount: 0,
        discarded: [],
      );

      expect(report.toJson()['discarded'], isEmpty);
    });
  });

  group('XtreamDiscard — serialización', () {
    test('toJson/fromJson conservan action y reason', () {
      const discard = XtreamDiscard(action: 'get_series', reason: 'XtreamMalformed(HTML)');

      final roundTripped = XtreamDiscard.fromJson(discard.toJson());

      expect(roundTripped.action, discard.action);
      expect(roundTripped.reason, discard.reason);
    });
  });
}
