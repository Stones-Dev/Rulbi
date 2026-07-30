import 'dart:async';
import 'dart:io';

import 'package:iptv_protocols/src/xmltv/xmltv_entry.dart';
import 'package:iptv_protocols/src/xmltv/xmltv_parser.dart';
import 'package:iptv_protocols/src/xmltv/xmltv_window.dart';
import 'package:test/test.dart';

/// Prueba de estrés de T1.3 (no es un micro-benchmark de tiempo como
/// `m3u_parser_benchmark_test.dart`): el *Hecho cuando* de Notion para
/// "Parser XMLTV (TDD)" es de memoria, no de velocidad — "dump de
/// cientos de MB parseado sin OOM y con memoria estable". Usa la API
/// pública con isolate real (`parseXmltv`), no el núcleo sin isolate: es
/// el camino de producción de verdad, y el RSS del proceso incluye al
/// isolate worker (mismo proceso del sistema operativo en el VM
/// standalone de Dart), así que sigue siendo una medida real.
///
/// Gateado por la existencia del fixture, igual que
/// `m3u_parser_benchmark_test.dart` (T1.5b): no es gate de CI, se salta
/// limpiamente si `tool/fetch_fixtures.dart` no se ha ejecutado. Puede
/// tardar varios minutos (~1.6 GB de XML descomprimido) — se loguea
/// progreso cada 5 s para distinguir "trabajando" de "colgado".
void main() {
  const path = 'test/fixtures/m3u/large/epgshare01_all_sources.xml.gz';

  test(
    'estrés: XMLTV agregado de epgshare01 (~193 MB comprimidos, ~1.6 GB '
    'descomprimidos) sin OOM y con memoria estable',
    () async {
      if (!File(path).existsSync()) {
        markTestSkipped(
          '$path no está presente localmente — '
          'ejecuta `dart run tool/fetch_fixtures.dart` primero. '
          'No es un fallo: el fixture es gitignored a propósito (T1.1).',
        );
        return;
      }

      // Ventana de producción real: es el caso que importa medir — con
      // un XMLTV real, casi todo el archivo cae fuera y se descarta al
      // vuelo (ver outOfWindowProgrammes en el resultado).
      final window = XmltvWindow.around(DateTime.now().toUtc());

      final stopwatch = Stopwatch()..start();
      var channelCount = 0;
      var programmeCount = 0;
      final rssSamplesMb = <int>[];

      void sample() {
        final rssMb = (ProcessInfo.currentRss / (1024 * 1024)).round();
        rssSamplesMb.add(rssMb);
        // ignore: avoid_print
        print(
          '[${stopwatch.elapsed.inSeconds}s] canales=$channelCount '
          'programas=$programmeCount RSS=${rssMb}MB',
        );
      }

      final sampler = Timer.periodic(
        const Duration(seconds: 5),
        (_) => sample(),
      );

      final outcome = parseXmltv(
        bytes: File(path).openRead(),
        window: window,
      );
      await for (final entry in outcome.entries) {
        switch (entry) {
          case XmltvChannelEntry():
            channelCount++;
          case XmltvProgrammeEntry():
            programmeCount++;
        }
      }
      final report = await outcome.report;

      sampler.cancel();
      sample(); // muestra final, con los contadores ya cerrados.
      stopwatch.stop();

      final maxRssMb = rssSamplesMb.reduce((a, b) => a > b ? a : b);

      // ignore: avoid_print
      print(
        'Estrés XMLTV: $channelCount canales, $programmeCount programas '
        'dentro de ventana (${report.outOfWindowProgrammes} fuera de '
        'ventana, ${report.discardedCount} descartes), '
        '${stopwatch.elapsed.inSeconds}s, RSS máximo ${maxRssMb}MB.',
      );

      expect(channelCount, greaterThan(0));
      expect(programmeCount, greaterThanOrEqualTo(0));
      // No es una cifra de producto — es un techo de sanity. Ver
      // docs/bench/T1.3-xmltv-stress.md para la cifra real medida y su
      // interpretación (esto es sanity check, no gate de CI, igual que
      // el benchmark de M3U).
      expect(
        maxRssMb,
        lessThan(2000),
        reason:
            'RSS máximo por encima de 2 GB con un input de ~1.6 GB '
            'descomprimidos sugeriría que el streaming no es tan '
            'streaming como debería.',
      );
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
