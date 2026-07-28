import 'dart:io';

import 'package:iptv_protocols/src/m3u/m3u_core_parser.dart';
import 'package:test/test.dart';

/// Smoke test sobre los 7 fixtures reales de T1.1 (m3u/real/): listas
/// públicas reales (iptv-org, kodinerds, iprd-org), no sintéticas. No
/// hace aserciones de contenido exacto (eso lo cubren los tests de
/// dialecto y de encoding) — solo que el parser termina sin excepción,
/// produce canales, y que cualquier descarte quede reportado y sea
/// pequeño frente al volumen real (P7: tolerante, nunca silencioso).
const _realFixtures = <String, int>{
  // nombre de archivo -> mínimo de canales esperado (holgado, no exacto:
  // son listas públicas que cambian con el tiempo)
  'iptv_org_news.m3u': 50,
  'iptv_org_sports.m3u': 30,
  'iptv_org_fr.m3u': 10,
  'iptv_org_us.m3u': 50,
  'iptv_org_es_samsung.m3u': 1,
  'kodinerds_clean_tv.m3u': 10,
  'iprd_all_stations.m3u': 100,
};

void main() {
  group('parseM3uCore — smoke test sobre fixtures reales (T1.1 m3u/real/)', () {
    for (final entry in _realFixtures.entries) {
      test('${entry.key}: parsea sin excepción, produce canales', () async {
        final path = 'test/fixtures/m3u/real/${entry.key}';
        final channelCount = <void>[];
        final discarded = <String>[];

        await for (final event in parseM3uCore(
          bytes: File(path).openRead(),
          sourceId: 'smoke-${entry.key}',
        )) {
          switch (event) {
            case M3uChannelBatch(:final channels):
              channelCount.addAll(List.filled(channels.length, null));
            case M3uDiscard(:final line):
              discarded.add('#${line.lineNumber}: ${line.reason}');
          }
        }

        expect(
          channelCount.length,
          greaterThanOrEqualTo(entry.value),
          reason: 'esperaba al menos ${entry.value} canales en ${entry.key}',
        );

        // Tolerancia, no cero absoluto: son listas públicas reales, no
        // fixtures sintéticos perfectos. El umbral es generoso (< 1% de
        // descartes sobre el total) — si una lista real empieza a superar
        // esto, es señal real de un dialecto no cubierto (P7: se
        // convierte en golden file nuevo antes de tocar el parser).
        final ratio = discarded.length / (channelCount.length + discarded.length);
        expect(
          ratio,
          lessThan(0.01),
          reason:
              'demasiados descartes en ${entry.key} '
              '(${discarded.length} de ${channelCount.length + discarded.length}): '
              '${discarded.take(5).join('; ')}',
        );
      });
    }
  });
}
