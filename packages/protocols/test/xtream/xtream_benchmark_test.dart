import 'dart:async';
import 'dart:io';

import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_protocols/src/xtream/xtream_client.dart';
import 'package:test/test.dart';

import 'support/fake_xtream_transport.dart';

/// T1.4 — Micro-benchmark de sanity, mismo espíritu que
/// `packages/protocols/test/m3u/m3u_parser_benchmark_test.dart`: **no** es
/// el pipeline completo de extremo a extremo (eso sería una T1.4b en
/// `packages/data`, no pedida por esta tarea) — solo confirma que
/// `importChannels()` (fetch + mapeo a `Channel`) no se cae ni se cuelga
/// con un panel grande, y mide dónde anda su tiempo/memoria/jank. No es
/// gate de CI: si el fixture no está generado localmente
/// (`dart run tool/generate_bench_xtream.dart`), se salta con un mensaje.
///
/// El punto que este benchmark decide (ver doc de
/// `XtreamClient.importChannels`): el bucle de mapeo cede el event loop
/// cada `cessionInterval` canales en vez de decodificar+mapear dentro de
/// un `Isolate` dedicado (a diferencia de `parseM3u`). Si los ticks de
/// jank de aquí superan el presupuesto de forma sistemática, la resolución
/// documentada es escalar a un isolate — el mismo criterio de "medir antes
/// de complicar" que ya siguió T1.6b con el upsert diferencial.
void main() {
  const path = 'test/fixtures/xtream/large/bench_50k_live_streams.json';
  const categoriesFixture = 20;

  group('XtreamClient.importChannels — 9 fixtures reales (ruido)', () {
    test('tiempo despreciable contra el panel real de T1.1', () async {
      final client = XtreamClient(
        host: Uri.parse('http://127.0.0.1:8081'),
        username: 'test',
        password: 'test',
        transport: FakeXtreamTransport(),
      );

      final stopwatch = Stopwatch()..start();
      final outcome = client.importChannels(sourceId: 'bench-real');
      final channels = await outcome.channels.toList();
      await outcome.report;
      stopwatch.stop();

      expect(channels, hasLength(4)); // 2 live + 1 vod + 1 serie, ver dialect_o0zz/
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
    });
  });

  group('XtreamClient.importChannels — 50k live streams sintéticos', () {
    test(
      'sanity: mapea 50k canales sin excepción, con jank dentro de presupuesto',
      () async {
        if (!File(path).existsSync()) {
          markTestSkipped(
            '$path no está presente localmente — '
            'ejecuta `dart run tool/generate_bench_xtream.dart` primero. '
            'No es un fallo: el fixture es gitignored a propósito (T1.4, '
            'mismo criterio que bench_100k.m3u de T1.5b).',
          );
          return;
        }

        final categories = [
          for (var i = 0; i < categoriesFixture; i++)
            {'category_id': '${100 + i}', 'category_name': 'Categoria $i', 'parent_id': 0},
        ];
        final fake = FakeXtreamTransport()
          ..enqueue('get_live_categories', jsonResponse(categories))
          ..enqueue('get_vod_categories', jsonResponse(<Object?>[]))
          ..enqueue('get_series_categories', jsonResponse(<Object?>[]))
          ..enqueue(
            'get_live_streams',
            rawResponse(File(path).readAsBytesSync(), contentType: 'application/json'),
          )
          ..enqueue('get_vod_streams', jsonResponse(<Object?>[]))
          ..enqueue('get_series', jsonResponse(<Object?>[]));

        final client = XtreamClient(
          host: Uri.parse('http://127.0.0.1:8081'),
          username: 'test',
          password: 'test',
          transport: fake,
        );

        final jank = _JankMonitor()..start();
        final rssStart = _currentRss();
        final stopwatch = Stopwatch()..start();

        final outcome = client.importChannels(sourceId: 'bench-50k');
        var count = 0;
        await for (final channel in outcome.channels) {
          count++;
          expect(channel.type, ContentType.live);
        }
        final report = await outcome.report;

        stopwatch.stop();
        jank.stop();
        final rssPeak = _currentRss();

        final jankGaps = jank.gapsMs;
        final jankMax = jankGaps.isEmpty ? 0 : jankGaps.reduce((a, b) => a > b ? a : b);
        final overBudget = jankGaps.where((g) => g > 32).length;

        final summary =
            'Benchmark de sanity T1.4 (50k live streams): '
            '$count canales, ${report.discardedCount} descartes, '
            '${stopwatch.elapsedMilliseconds} ms, '
            'RSS ${_humanBytes(rssStart)} -> ${_humanBytes(rssPeak)}, '
            'jank máx $jankMax ms, ticks > 32 ms: $overBudget/${jankGaps.length}.';
        // ignore: avoid_print
        print(summary);

        expect(count, 50000);
        expect(report.discardedCount, 0);
        expect(
          stopwatch.elapsed,
          lessThan(const Duration(seconds: 10)),
          reason: 'sanity check, no gate de CI — ver docs/bench/T1.4-xtream-50k.md.',
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}

/// Detector de jank: un `Timer.periodic` de 16 ms (presupuesto de frame a
/// 60 fps) armado en el isolate raíz — mismo diseño que el de
/// `packages/data/test/import_100k_benchmark_test.dart` (T1.5b/T1.6b),
/// reimplementado aquí en vez de compartido porque `protocols` no depende
/// de `data` (regla de capas, P6) y no existe hoy un paquete de utilidades
/// de test compartido entre ambos.
class _JankMonitor {
  final _stopwatch = Stopwatch();
  final _gapsMs = <int>[];
  Timer? _timer;

  void start() {
    _stopwatch.start();
    var lastMs = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final nowMs = _stopwatch.elapsedMilliseconds;
      _gapsMs.add(nowMs - lastMs);
      lastMs = nowMs;
    });
  }

  void stop() {
    _timer?.cancel();
    _stopwatch.stop();
  }

  List<int> get gapsMs => List.unmodifiable(_gapsMs);
}

int _currentRss() {
  try {
    return ProcessInfo.currentRss;
  } on Object {
    return -1;
  }
}

String _humanBytes(int bytes) {
  if (bytes < 0) return 'n/d';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
