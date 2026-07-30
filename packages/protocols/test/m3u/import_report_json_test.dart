import 'dart:io';

import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_protocols/src/m3u/import_report.dart';
import 'package:iptv_protocols/src/m3u/m3u_core_parser.dart';
import 'package:test/test.dart';

const _dir = 'test/fixtures/m3u/edge_cases';

/// T1.9: el informe de descartes ya existe (T1.2) — esta batería prueba que
/// se serializa a un JSON estable, con un descarte REAL (no inventado)
/// producido por un fixture ya comiteado del repo.
Future<ImportReport> _parseReport(String fileName) async {
  final channels = <Channel>[];
  final discarded = <DiscardedLine>[];
  await for (final event in parseM3uCore(
    bytes: File('$_dir/$fileName').openRead(),
    sourceId: 's1',
  )) {
    switch (event) {
      case M3uChannelBatch(channels: final batch):
        channels.addAll(batch);
      case M3uDiscard(:final line):
        discarded.add(line);
    }
  }
  return ImportReport(
    parsed: channels.length,
    discarded: List.unmodifiable(discarded),
  );
}

void main() {
  group('ImportReport.toJson', () {
    test(
      'pipe_user_agent_referer.m3u (issue #57 real de 4gray/iptvnator): '
      '1 canal + 1 descarte real, JSON estable',
      () async {
        final report = await _parseReport('pipe_user_agent_referer.m3u');

        expect(report.parsed, 1);
        expect(report.discarded, hasLength(1));

        expect(report.toJson(), {
          'kind': 'm3u',
          'parsed': 1,
          'discardedCount': 1,
          'discarded': [
            {
              'lineNumber': 8,
              'rawLine':
                  'https://www.streamaway.net/fra/histo/index.m3u8|'
                  'Referer=https://www.streamaway.net/fr/Histoire-fr.php',
              'reason': 'URL sin #EXTINF previo',
            },
          ],
        });
      },
    );

    test('round-trip toJson -> fromJson -> toJson es estable', () async {
      final report = await _parseReport('pipe_user_agent_referer.m3u');

      final json = report.toJson();
      final roundTripped = ImportReport.fromJson(json);

      expect(roundTripped.parsed, report.parsed);
      expect(roundTripped.discarded, report.discarded);
      expect(roundTripped.toJson(), json);
    });

    test('un informe sin descartes serializa una lista vacía', () {
      const report = ImportReport(parsed: 3, discarded: []);

      expect(report.toJson(), {
        'kind': 'm3u',
        'parsed': 3,
        'discardedCount': 0,
        'discarded': <Map<String, Object?>>[],
      });
    });
  });
}
