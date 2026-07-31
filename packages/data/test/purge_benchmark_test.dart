@Tags(['benchmark'])
library;

import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_data/iptv_data.dart';

/// Benchmark de sanity de las dos purgas de S2 (lección de T1.4: medir
/// antes de suponer — el jsonDecode síncrono de Xtream escondía 149 ms de
/// jank hasta que se midió). No es gate de CI (`@Tags(['benchmark'])`,
/// mismo criterio que `import_100k_benchmark_test.dart`), pero SÍ corre
/// en esta sesión antes de cerrar las tareas.
///
/// Escenario: 50k canales (40k tumbados — 5k con favorito vivo, 5k con
/// watch-state vivo, 30k huérfanos purgables) + 100k programas EPG (90k
/// fuera de ventana, 10k dentro). Se ejerce `DefaultRunPurge.runOnce`
/// (core) sobre los dos repositorios reales de `data` — el mismo camino
/// que usará el `PurgeScheduler` en producción, no las purgas aisladas.
///
/// Presupuesto: gap máximo del event loop < 100 ms durante la purga (más
/// laxo que los 32 ms de RNF-01 para import — este es un chequeo de
/// sanity de una operación de mantenimiento en segundo plano, no un path
/// interactivo).
void main() {
  test(
    '50k canales (40k tumbados) + 100k programas EPG: purga sin jank grave',
    () async {
      final tempDir = await Directory.systemTemp.createTemp('purge_bench_');
      addTearDown(() async {
        if (tempDir.existsSync()) await tempDir.delete(recursive: true);
      });
      final dbFile = File('${tempDir.path}/purge_bench.sqlite');

      final db = IptvDatabase(NativeDatabase.createInBackground(dbFile));
      addTearDown(db.close);

      final channels = DriftChannelRepository(db);
      final epg = DriftEpgRepository(db);

      final now = DateTime.utc(2026, 3, 10);
      final tombstonedAt = now.subtract(const Duration(days: 40)); // > gracia (30d)

      const totalChannels = 50000;
      const aliveChannels = 10000; // reaparecen en el 2º import -> vivos
      const favoriteProtected = 5000;
      const watchStateProtected = 5000;
      // El resto de los 40k tumbados (30000) queda huérfano -> purgable.

      Channel channelFor(int i) => Channel(
        ref: ChannelRef(sourceId: 'bench', key: 'canal-$i'),
        sourceId: 'bench',
        type: ContentType.live,
        name: 'Canal $i',
        url: Uri.parse('http://example.com/$i'),
      );

      // 1er import: los 50k, con el DriftChannelRepository real (mismo
      // camino de producción, no un INSERT crudo).
      await channels.importSourceContent(
        'bench',
        Stream.fromIterable(Iterable.generate(totalChannels, channelFor)),
        now: DateTime.utc(2026, 1, 1),
      );

      // 2º import: solo reaparecen los "vivos" (i >= 40000) -> los otros
      // 40000 se tumban de verdad por el propio upsert diferencial
      // (T1.6b), con `tombstonedAt` como instante del tombstone.
      await channels.importSourceContent(
        'bench',
        Stream.fromIterable(
          Iterable.generate(
            aliveChannels,
            (i) => channelFor(totalChannels - aliveChannels + i),
          ),
        ),
        now: tombstonedAt,
      );

      // Toda la siembra sintética (favoritos/watch-state/EPG) pasa por
      // este mismo helper de lotes vía `db.batch()` — nunca un upsert por
      // fila a través del repositorio uno a uno: 10k round-trips
      // secuenciales al isolate de fondo de sqlite3 resultaron viables en
      // local pero muy por encima del presupuesto en el runner Windows de
      // CI, mucho más lento de I/O (hallazgo real: la 1ª corrida de este
      // benchmark hizo justo eso para favoritos/watch-state y agotó el
      // timeout de 5 min en CI sin que localmente se notara).
      const seedBatch = 2000;
      Future<void> seedInChunks(
        int start,
        int end,
        void Function(Batch b, int i) insertOne,
      ) async {
        for (var offset = start; offset < end; offset += seedBatch) {
          final chunkEnd = (offset + seedBatch).clamp(start, end);
          await db.batch((b) {
            for (var i = offset; i < chunkEnd; i++) {
              insertOne(b, i);
            }
          });
        }
      }

      // Protege 5k con favorito vivo y 5k con watch-state vivo, entre los
      // 40k tumbados (i en [0, 40000)).
      await seedInChunks(0, favoriteProtected, (b, i) {
        b.insert(
          db.favorites,
          FavoritesCompanion.insert(
            sourceId: 'bench',
            refKey: 'canal-$i',
            updatedAt: Value(tombstonedAt),
          ),
        );
      });
      await seedInChunks(
        favoriteProtected,
        favoriteProtected + watchStateProtected,
        (b, i) {
          b.insert(
            db.watchState,
            WatchStateCompanion.insert(
              sourceId: 'bench',
              refKey: 'canal-$i',
              positionMs: const Value(5 * 60 * 1000),
              durationMs: const Value(50 * 60 * 1000),
              updatedAt: Value(tombstonedAt),
            ),
          );
        },
      );

      // 100k programas EPG sembrados a mano (no hay escritor XMLTV->drift
      // todavía, ver epg_purge_test.dart): 45k en el pasado lejano, 45k en
      // el futuro lejano (90k fuera de la ventana −1d/+7d por defecto),
      // 10k dentro.
      const totalProgrammes = 100000;
      const outOfWindowEach = 45000;

      Future<void> seedProgrammes(
        int count,
        DateTime Function(int i) startFor,
        String prefix,
      ) => seedInChunks(0, count, (b, i) {
        final start = startFor(i);
        b.insert(
          db.epgProgrammes,
          EpgProgrammesCompanion.insert(
            tvgId: '$prefix-$i',
            start: start,
            stop: start.add(const Duration(minutes: 30)),
            title: 'Programa $prefix $i',
          ),
        );
      });

      await seedProgrammes(
        outOfWindowEach,
        (i) => now.subtract(Duration(days: 30, minutes: i)),
        'pasado',
      );
      await seedProgrammes(
        outOfWindowEach,
        (i) => now.add(Duration(days: 30, minutes: i)),
        'futuro',
      );
      await seedProgrammes(
        totalProgrammes - 2 * outOfWindowEach,
        (i) => now.add(Duration(minutes: i)),
        'vivo',
      );

      // ─── La purga real, con el detector de jank armado ───────────────
      final runPurge = DefaultRunPurge(epg, channels, _FixedClock(now));
      final jank = _JankMonitor()..start();

      final stats = await runPurge.runOnce();

      jank.stop();

      // ignore: avoid_print
      print(
        '\n=== Benchmark de sanity de purgas (S2) ===\n'
        '  EPG purgado: ${stats.epgProgrammes} (esperado '
        '${2 * outOfWindowEach})\n'
        '  Tombstones purgados: ${stats.channelTombstones} (esperado '
        '${totalChannels - aliveChannels - favoriteProtected - watchStateProtected})\n'
        '  Jank: gaps=${jank.gapsMs.length}, máx=${jank.jankMaxMs} ms, '
        'ticks > 100 ms: ${jank.gapsMs.where((g) => g > 100).length}\n',
      );

      // Verificación semántica: no solo "no hubo jank", también que la
      // purga hizo lo correcto a esta escala (45k pasado + 45k futuro).
      expect(stats.epgProgrammes, 2 * outOfWindowEach);
      expect(
        stats.channelTombstones,
        totalChannels - aliveChannels - favoriteProtected - watchStateProtected,
      );

      expect(
        jank.jankMaxMs,
        lessThan(100),
        reason:
            'Sanity de S2: gap máximo del event loop durante la purga de '
            '50k canales/100k programas EPG. Gap real: ${jank.jankMaxMs} ms '
            '— si esto salta, hay que revisar el tamaño de lote antes de '
            'cerrar la sesión (lección de T1.4: los 149 ms de jank del '
            'jsonDecode síncrono).',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

final class _FixedClock implements Clock {
  const _FixedClock(this._now);
  final DateTime _now;

  @override
  DateTime now() => _now;
}

/// Mismo detector que `import_100k_benchmark_test.dart` (T1.5b): un
/// `Timer.periodic` de 16 ms armado en el isolate raíz mide la latencia
/// real entre ticks del event loop — un bloque síncrono largo se ve como
/// un gap grande.
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
  int get jankMaxMs => _gapsMs.isEmpty
      ? 0
      : _gapsMs.fold<int>(0, (a, b) => a > b ? a : b);
}
