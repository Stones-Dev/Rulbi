@Tags(['benchmark'])
library;

import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show QueryExecutor;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_data/iptv_data.dart';
import 'package:iptv_protocols/iptv_protocols.dart';

/// T1.5b — Benchmark 100k (RNF-01; Notion "Hecho cuando": "100k canales
/// < 30 s con hilo de UI libre (medido)"). A diferencia de
/// `benchmark_test.dart` (canales SINTÉTICOS, solo capa de BD) y de
/// `m3u_parser_benchmark_test.dart` en `packages/protocols` (solo parser,
/// sin escritura), este test mide el pipeline COMPLETO de extremo a
/// extremo: parser M3U real (isolate) → `DriftChannelRepository
/// .importSourceContent` (upsert diferencial, T1.6b) → búsqueda FTS5,
/// contra el fixture real de 100k
/// que genera `tool/generate_bench_m3u.dart` (8 réplicas del catálogo real
/// de iptv-org, truncadas a 100.000 en un límite de bloque — ver la
/// cabecera de ese script para el método completo).
///
/// **Por qué "disco" usa `NativeDatabase.createInBackground`, no
/// `NativeDatabase(file)` a secas**: la apertura de producción real
/// (`IptvDatabase.open()`, `packages/data/lib/src/db/database.dart`) pasa
/// por `driftDatabase()` de `drift_flutter`, que **por defecto** (cuando
/// `shareAcrossIsolates` no está activado — nuestro caso) abre la conexión
/// con `NativeDatabase.createBackgroundConnection` (ver
/// `drift_flutter-0.3.1/lib/src/native.dart:131`, verificado en el paquete
/// instalado): el trabajo de sqlite3 vive en un isolate aparte, y cada
/// `insert()` es un mensaje real entre isolates. Un `NativeDatabase(file)`
/// directo (lo que usan los benchmarks existentes del repo, y lo que usaba
/// una primera versión de este test) ejecuta sqlite3 de forma **síncrona
/// en el isolate llamador** — un patrón que este mismo benchmark demostró
/// que satura la cola de microtasks y bloquea el `Timer` de detección de
/// jank casi por completo (~97 % de los ticks sobre presupuesto en una
/// corrida de sondeo). Medir "sin congelar la UI" contra ese patrón habría
/// sido medir un caso que la app real no usa. Ver
/// `docs/bench/T1.5b-import-100k.md` § Nota metodológica para el detalle.
///
/// Metodología, cifras publicadas y cómo reproducir:
/// `docs/bench/T1.5b-import-100k.md`. Etiquetado `benchmark`: NO es gate de
/// CI, y se salta limpiamente si el fixture no está generado localmente
/// (mismo patrón que el benchmark de sanity de `packages/protocols`).
void main() {
  const fixturePath = '../protocols/test/fixtures/m3u/large/bench_100k.m3u';
  const warmupFixturePath =
      '../protocols/test/fixtures/m3u/large/iptv_org_index.m3u';
  final fixtureFile = File(fixturePath);

  test(
    'importación de 100k canales de extremo a extremo (parser real + drift + FTS5)',
    () async {
      if (!fixtureFile.existsSync()) {
        markTestSkipped(
          '$fixturePath no está presente localmente. Genera el fixture '
          'desde la raíz del repo:\n'
          '  dart run tool/fetch_fixtures.dart --only=iptv_org_index\n'
          '  dart run tool/generate_bench_m3u.dart\n'
          'No es un fallo — ver docs/bench/T1.5b-import-100k.md.',
        );
        return;
      }

      // Warmup descartado (no se mide): calienta JIT, arranque del isolate
      // del parser y el driver sqlite3 nativo con un dataset más pequeño
      // (el índice real de 13.560 canales, no un sub-conjunto artificial de
      // bench_100k) para no pagar dos veces el coste completo de 100k.
      final warmupFile = File(warmupFixturePath);
      if (warmupFile.existsSync()) {
        final warmupDb = IptvDatabase(NativeDatabase.memory());
        await DriftChannelRepository(warmupDb).importSourceContent(
          'warmup',
          parseM3u(bytes: warmupFile.openRead(), sourceId: 'warmup').channels,
          now: DateTime.now(),
        );
        await warmupDb.close();
      }

      // Suelo teórico de throughput puro (sqlite3 síncrono en el mismo
      // isolate, sin coste de IPC). Su cifra de jank NO es representativa
      // de producción (ver nota de cabecera) — se reporta solo el tiempo
      // total y la búsqueda como contexto de la mejor cota posible.
      final memoryReport = await _benchmarkStorage(
        label:
            'memoria, mismo isolate (NativeDatabase.memory()) — '
            'suelo teórico de throughput, jank NO representativo',
        fixtureFile: fixtureFile,
        openConnection: () => NativeDatabase.memory(),
        cleanup: () async {},
      );

      // Caso real: mismo patrón que IptvDatabase.open() en producción —
      // isolate de fondo para sqlite3 (ver nota de cabecera). Esta es la
      // pasada cuyo número decide el veredicto de RNF-01.
      final tempDir = await Directory.systemTemp.createTemp('t15b_bench_');
      final dbFile = File('${tempDir.path}/bench.sqlite');
      final diskReport = await _benchmarkStorage(
        label:
            'disco, isolate de fondo (NativeDatabase.createInBackground, '
            'igual que IptvDatabase.open() en producción) — caso real',
        fixtureFile: fixtureFile,
        openConnection: () {
          if (dbFile.existsSync()) dbFile.deleteSync();
          return NativeDatabase.createInBackground(dbFile);
        },
        cleanup: () async {
          if (tempDir.existsSync()) await tempDir.delete(recursive: true);
        },
      );

      // ignore: avoid_print
      print(_renderReport(memoryReport, diskReport));

      // Veredicto RNF-01 / "Hecho cuando" de Notion: la cifra de referencia
      // es la de DISCO (caso real); memoria es el suelo teórico y se
      // reporta como contexto, no como el número que cierra la tarea.
      expect(
        diskReport.medianTotalMs,
        lessThan(30000),
        reason:
            'RNF-01 / Notion "Hecho cuando": 100k canales < 30 s. '
            'Mediana real (disco, 3 corridas ${diskReport.totalMsRuns}): '
            '${diskReport.medianTotalMs} ms.',
      );
      expect(
        diskReport.detail.searchP95Ms,
        lessThan(100),
        reason:
            'RNF-01: búsqueda FTS5 < 100 ms tras importar. '
            'p95 real: ${diskReport.detail.searchP95Ms.toStringAsFixed(1)} ms.',
      );
      expect(
        diskReport.detail.jankMaxMs,
        lessThan(32),
        reason:
            'RNF-01 "sin congelar la UI" — proxy de frame budget a 60 fps '
            '(latencia del event loop del isolate raíz, no un profiler de '
            'Flutter real; ver docs/bench/T1.5b-import-100k.md). '
            'Gap máximo real: ${diskReport.detail.jankMaxMs} ms.',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

// ─── Medición ────────────────────────────────────────────────────────────

class _BatchSample {
  _BatchSample(this.count, this.elapsedMs, this.rssBytes);
  final int count;
  final int elapsedMs;
  final int rssBytes;
}

class _DetailMetrics {
  _DetailMetrics({
    required this.batchSamples,
    required this.rssStartBytes,
    required this.rssPeakBytes,
    required this.searchLatenciesMs,
    required this.searchP95Ms,
    required this.jankGapsMs,
    required this.jankMaxMs,
    required this.jankP99Ms,
    required this.jankOverBudgetCount,
  });

  final List<_BatchSample> batchSamples;
  final int rssStartBytes;
  final int rssPeakBytes;

  /// Por consulta: latencias en ms, primera repetición ya descartada.
  final Map<String, List<double>> searchLatenciesMs;
  final double searchP95Ms;

  final List<int> jankGapsMs;
  final int jankMaxMs;
  final double jankP99Ms;
  final int jankOverBudgetCount;
}

class _StorageReport {
  _StorageReport({
    required this.label,
    required this.totalMsRuns,
    required this.medianTotalMs,
    required this.pureParseMs,
    required this.detail,
  });

  final String label;
  final List<int> totalMsRuns;
  final int medianTotalMs;
  final int pureParseMs;
  final _DetailMetrics detail;
}

/// 3 repeticiones medidas del pipeline completo (parse+ingesta) contra un
/// backend de almacenamiento dado. Las métricas de diagnóstico (curva por
/// lote, RSS, jank, búsqueda) se capturan solo en la ÚLTIMA repetición: son
/// evidencia de dónde va el tiempo, no el número que se compara contra el
/// presupuesto — repetirlas 3x triplicaría la duración de la corrida sin
/// cambiar la mediana de tiempo total, que sí se mide las 3 veces.
Future<_StorageReport> _benchmarkStorage({
  required String label,
  required File fixtureFile,
  required QueryExecutor Function() openConnection,
  required Future<void> Function() cleanup,
}) async {
  const reps = 3;
  final totalMsRuns = <int>[];
  _DetailMetrics? detail;

  // Pasada de parseo puro (sin BD), una sola vez para este backend: el
  // parser no depende de dónde escribe drift, así que repetirla por rep no
  // aporta información nueva. Sirve para atribuir, por diferencia contra el
  // tiempo total, cuánto es "parseo" y cuánto "escritura" — una
  // aproximación, no una medida exacta, porque parser y escritura corren
  // solapados (productor/consumidor sobre el mismo event loop); se
  // documenta como tal en el reporte.
  final pureParseSw = Stopwatch()..start();
  await for (final _ in parseM3u(
    bytes: fixtureFile.openRead(),
    sourceId: 'bench-parse-only',
  ).channels) {
    // solo se cronometra el drenaje del stream.
  }
  pureParseSw.stop();
  final pureParseMs = pureParseSw.elapsedMilliseconds;

  for (var rep = 0; rep < reps; rep++) {
    final captureDetail = rep == reps - 1;
    final db = IptvDatabase(openConnection());
    final repo = DriftChannelRepository(db);

    final jank = captureDetail ? (_JankMonitor()..start()) : null;
    final batchSamples = <_BatchSample>[];
    var nextSampleAt = 5000;

    final totalSw = Stopwatch()..start();
    final outcome = parseM3u(bytes: fixtureFile.openRead(), sourceId: 'bench');

    var seen = 0;
    Stream<Channel> instrumented() async* {
      await for (final channel in outcome.channels) {
        seen++;
        if (captureDetail && seen >= nextSampleAt) {
          batchSamples.add(
            _BatchSample(seen, totalSw.elapsedMilliseconds, _currentRss()),
          );
          nextSampleAt += 5000;
        }
        yield channel;
      }
    }

    final rssStart = _currentRss();
    await repo.importSourceContent('bench', instrumented(), now: DateTime.now());
    await outcome.report; // completa tras agotar el stream; solo se espera.
    totalSw.stop();
    jank?.stop();

    expect(
      seen,
      100000,
      reason:
          'El fixture debe producir exactamente 100.000 canales parseados '
          '(vio $seen). Si esto falla, revisa tool/generate_bench_m3u.dart '
          'o regenera el fixture — el benchmark no es válido con otro conteo.',
    );

    totalMsRuns.add(totalSw.elapsedMilliseconds);

    if (captureDetail) {
      final rssPeak = batchSamples.isEmpty
          ? rssStart
          : batchSamples
                .map((s) => s.rssBytes)
                .fold<int>(0, (a, b) => a > b ? a : b);

      const queries = {
        'frecuente ("general")': 'general',
        'raro con acento (espana~España)': 'espana',
        'prefijo (esp*)': 'esp*',
      };
      final searchLatencies = <String, List<double>>{};
      for (final entry in queries.entries) {
        final samples = <double>[];
        for (var i = 0; i < 6; i++) {
          final sw = Stopwatch()..start();
          await repo.search(entry.value, limit: 200);
          sw.stop();
          if (i == 0) continue; // descarta la primera (calentamiento caché).
          samples.add(sw.elapsedMicroseconds / 1000);
        }
        searchLatencies[entry.key] = samples;
      }
      final allSearchSamples = searchLatencies.values.expand((l) => l).toList()
        ..sort();
      final searchP95 = _percentile(allSearchSamples, 0.95);

      final jankGapsMs = jank?.gapsMs ?? const <int>[];
      final jankMax = jankGapsMs.isEmpty
          ? 0
          : jankGapsMs.fold<int>(0, (a, b) => a > b ? a : b);
      final jankP99 = _percentile(
        jankGapsMs.map((g) => g.toDouble()).toList()..sort(),
        0.99,
      );
      final overBudget = jankGapsMs.where((g) => g > 32).length;

      detail = _DetailMetrics(
        batchSamples: batchSamples,
        rssStartBytes: rssStart,
        rssPeakBytes: rssPeak,
        searchLatenciesMs: searchLatencies,
        searchP95Ms: searchP95,
        jankGapsMs: jankGapsMs,
        jankMaxMs: jankMax,
        jankP99Ms: jankP99,
        jankOverBudgetCount: overBudget,
      );
    }

    await db.close();
  }

  await cleanup();

  final sorted = List<int>.of(totalMsRuns)..sort();
  final median = sorted[reps ~/ 2];

  return _StorageReport(
    label: label,
    totalMsRuns: totalMsRuns,
    medianTotalMs: median,
    pureParseMs: pureParseMs,
    detail: detail!,
  );
}

/// Detector de jank: un `Timer.periodic` de 16 ms (presupuesto de frame a
/// 60 fps) armado en el isolate raíz. Mide la latencia real entre ticks del
/// event loop — un proxy del frame budget, no un profiler de Flutter (este
/// test no tiene UI). Un bloque síncrono largo (p. ej. un `batch()` de
/// drift enorme) se vería como un gap grande entre ticks.
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

double _percentile(List<double> sortedAscending, double p) {
  if (sortedAscending.isEmpty) return 0;
  final idx = ((sortedAscending.length - 1) * p).round();
  return sortedAscending[idx];
}

// ─── Reporte ─────────────────────────────────────────────────────────────

String _renderReport(_StorageReport memory, _StorageReport disk) {
  final buffer = StringBuffer()
    ..writeln()
    ..writeln('=== T1.5b — Benchmark 100k (RNF-01) ===');

  for (final r in [memory, disk]) {
    buffer
      ..writeln()
      ..writeln('--- ${r.label} ---')
      ..writeln('  Parseo puro (sin BD): ${r.pureParseMs} ms')
      ..writeln(
        '  Total (parse+ingesta), 3 corridas: ${r.totalMsRuns} ms '
        '— mediana: ${r.medianTotalMs} ms',
      )
      ..writeln(
        '  Escritura atribuida (mediana total - parseo puro, aproximado): '
        '${r.medianTotalMs - r.pureParseMs} ms',
      )
      ..writeln(
        '  RSS inicial: ${_humanBytes(r.detail.rssStartBytes)} '
        '— RSS pico: ${_humanBytes(r.detail.rssPeakBytes)}',
      )
      ..writeln('  Curva por lote (cada 5000 canales, última repetición):');
    for (final s in r.detail.batchSamples) {
      buffer.writeln(
        '    ${s.count}: ${s.elapsedMs} ms, RSS ${_humanBytes(s.rssBytes)}',
      );
    }
    buffer.writeln(
      '  Búsqueda FTS5 (6 repeticiones por consulta, 1ª descartada):',
    );
    for (final entry in r.detail.searchLatenciesMs.entries) {
      final sorted = List<double>.of(entry.value)..sort();
      final median = sorted.isEmpty ? 0.0 : sorted[sorted.length ~/ 2];
      buffer.writeln(
        '    "${entry.key}": '
        '${entry.value.map((v) => v.toStringAsFixed(2)).toList()} ms '
        '— mediana ${median.toStringAsFixed(2)} ms',
      );
    }
    buffer
      ..writeln(
        '  p95 global de búsqueda: '
        '${r.detail.searchP95Ms.toStringAsFixed(2)} ms',
      )
      ..writeln(
        '  Jank (gap entre ticks de 16 ms): máx ${r.detail.jankMaxMs} ms, '
        'p99 ${r.detail.jankP99Ms.toStringAsFixed(1)} ms, '
        'ticks > 32 ms: ${r.detail.jankOverBudgetCount}/'
        '${r.detail.jankGapsMs.length}',
      );
  }
  return buffer.toString();
}

String _humanBytes(int bytes) {
  if (bytes < 0) return 'n/d';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
