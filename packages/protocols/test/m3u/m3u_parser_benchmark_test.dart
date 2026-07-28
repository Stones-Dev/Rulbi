import 'dart:io';

import 'package:iptv_protocols/iptv_protocols.dart';
import 'package:test/test.dart';

/// Micro-benchmark de sanity contra el catálogo completo de iptv-org
/// (fixture de T1.5b, no committeado — `dart run tool/fetch_fixtures.dart`
/// lo descarga bajo demanda a `m3u/large/`). **No es T1.5b**: no mide el
/// pipeline de importación completo (parser + `data`), solo confirma que
/// el parser en sí no se cae ni se cuelga con un archivo real grande, y
/// dónde anda su tiempo. No es gate de CI: si el fixture no está presente
/// localmente, el test se salta con un mensaje, no falla.
void main() {
  const path = 'test/fixtures/m3u/large/iptv_org_index.m3u';

  test(
    'sanity: parsea el catálogo completo de iptv-org sin excepción y en tiempo razonable',
    () async {
      if (!File(path).existsSync()) {
        markTestSkipped(
          '$path no está presente localmente — '
          'ejecuta `dart run tool/fetch_fixtures.dart` primero. '
          'No es un fallo: el fixture es gitignored a propósito (T1.1).',
        );
        return;
      }

      final stopwatch = Stopwatch()..start();
      final outcome = parseM3u(bytes: File(path).openRead(), sourceId: 'bench');

      var channelCount = 0;
      await for (final _ in outcome.channels) {
        channelCount++;
      }
      final report = await outcome.report;
      stopwatch.stop();

      // ignore: avoid_print
      print(
        'Benchmark de sanity: $channelCount canales, '
        '${report.discarded.length} descartes, '
        '${stopwatch.elapsedMilliseconds} ms.',
      );

      expect(channelCount, greaterThan(1000));
      expect(
        stopwatch.elapsed,
        lessThan(const Duration(seconds: 10)),
        reason:
            'sanity check, no gate de CI — si esto falla en una máquina '
            'razonable, algo se degradó de verdad en el parser.',
      );
    },
  );
}
