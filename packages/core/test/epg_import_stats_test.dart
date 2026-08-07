import 'package:iptv_core/iptv_core.dart';
import 'package:test/test.dart';

/// `EpgImportStats` (ADR-008, S5 · Ola 2) — análogo a
/// `SourceImportStats.toJson` (T1.9, `use_cases_test.dart`): claves en
/// orden fijo, round-trip estable.
void main() {
  group('EpgImportStats.toJson', () {
    test('serializa las 7 cuentas con claves en orden fijo', () {
      const stats = EpgImportStats(
        programmesInserted: 128,
        programmesUpdated: 12,
        programmesUnchanged: 13420,
        channelsInserted: 8,
        channelsUpdated: 2,
        channelsUnchanged: 40,
        duplicateKeys: 3,
      );

      expect(stats.toJson(), {
        'programmesInserted': 128,
        'programmesUpdated': 12,
        'programmesUnchanged': 13420,
        'channelsInserted': 8,
        'channelsUpdated': 2,
        'channelsUnchanged': 40,
        'duplicateKeys': 3,
      });
    });

    test('round-trip toJson -> fromJson -> toJson es estable', () {
      const stats = EpgImportStats(
        programmesInserted: 128,
        programmesUpdated: 12,
        programmesUnchanged: 13420,
        channelsInserted: 8,
        channelsUpdated: 2,
        channelsUnchanged: 40,
        duplicateKeys: 3,
      );

      final roundTripped = EpgImportStats.fromJson(stats.toJson());

      expect(roundTripped, stats);
      expect(roundTripped.toJson(), stats.toJson());
    });
  });
}
