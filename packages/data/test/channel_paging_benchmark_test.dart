@Tags(['benchmark'])
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_data/iptv_data.dart';

/// Benchmark de sanity del listado paginado (S5 · Ola 1, ui-spec §2.3):
/// sin `idx_channels_type_name` (`migration_v3_test.dart` confirma que la
/// consulta la usa), cada página de `ChannelPageCache` sería un scan+sort
/// completo de la tabla — inviable sobre 100k filas. **Sí es gate de CI**,
/// mismo criterio que `purge_benchmark_test.dart`: el tag solo documenta
/// que es lento, `dart_test.yaml` no lo excluye.
///
/// Escenario: 50k canales reales (mismo camino de producción,
/// `DriftChannelRepository.importSourceContent`, no un `INSERT` crudo),
/// repartidos en 50 categorías. Se mide `channelsPage` en un offset
/// profundo (la mitad de la tabla, el caso que un scan completo penaliza
/// más) y `countChannels` — las dos operaciones que fijan `itemCount` y
/// sirven cada página en `ChannelPageCache` (`apps/app`).
///
/// Presupuesto: p95 < 100 ms (RNF-01, el mismo que search en
/// `import_100k_benchmark_test.dart` — FTS5 midió 1.55 ms de p95 ahí; aquí
/// no hay FTS5 de por medio, solo el índice B-tree de `channels`, así que
/// el margen es aún más holgado si el índice se usa de verdad).
int get _budgetMs => Platform.environment['CI'] == 'true' ? 300 : 100;

void main() {
  test(
    '50k canales: channelsPage/countChannels en offset profundo dentro de presupuesto',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'channel_paging_bench_',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) await tempDir.delete(recursive: true);
      });
      final dbFile = File('${tempDir.path}/paging_bench.sqlite');

      final db = IptvDatabase(NativeDatabase.createInBackground(dbFile));
      addTearDown(db.close);

      final repository = DriftChannelRepository(db);

      const totalChannels = 50000;
      const categoryCount = 50;

      Channel channelFor(int i) => Channel(
        ref: ChannelRef(sourceId: 'bench', key: 'canal-$i'),
        sourceId: 'bench',
        categoryId: 'cat-${i % categoryCount}',
        type: ContentType.live,
        // Padding numérico para que el orden alfabético de `name` sea
        // estable y predecible al comprobar offsets.
        name: 'Canal ${i.toString().padLeft(6, '0')}',
        url: Uri.parse('http://example.com/$i'),
      );

      await repository.importSourceContent(
        'bench',
        Stream.fromIterable(Iterable.generate(totalChannels, channelFor)),
        now: DateTime.utc(2026, 1, 1),
      );

      const query = ChannelQuery(type: ContentType.live, sourceIds: {'bench'});

      Future<double> timeMs(Future<void> Function() op) async {
        final sw = Stopwatch()..start();
        await op();
        sw.stop();
        return sw.elapsedMicroseconds / 1000;
      }

      // 6 repeticiones, se descarta la primera (calentamiento de caché de
      // páginas de SQLite) — mismo criterio que
      // `import_100k_benchmark_test.dart`.
      final pageLatencies = <double>[];
      final countLatencies = <double>[];
      List<Channel> lastPage = const [];
      for (var i = 0; i < 6; i++) {
        final pageMs = await timeMs(() async {
          lastPage = await repository.channelsPage(
            query,
            offset: totalChannels ~/ 2,
            limit: 200,
          );
        });
        final countMs = await timeMs(() async {
          await repository.countChannels(query);
        });
        if (i == 0) continue;
        pageLatencies.add(pageMs);
        countLatencies.add(countMs);
      }

      double percentile(List<double> samples, double p) {
        final sorted = List<double>.of(samples)..sort();
        final index = (sorted.length * p).floor().clamp(0, sorted.length - 1);
        return sorted[index];
      }

      final pageP95 = percentile(pageLatencies, 0.95);
      final countP95 = percentile(countLatencies, 0.95);

      // ignore: avoid_print
      print(
        '\n=== Benchmark de sanity del listado paginado (S5 · Ola 1) ===\n'
        '  channelsPage p95: ${pageP95.toStringAsFixed(2)} ms '
        '(muestras: ${pageLatencies.map((v) => v.toStringAsFixed(2))})\n'
        '  countChannels p95: ${countP95.toStringAsFixed(2)} ms\n'
        '  presupuesto: $_budgetMs ms '
        '(${Platform.environment['CI'] == 'true' ? 'CI' : 'local'})\n',
      );

      expect(lastPage, hasLength(200));
      expect(lastPage.first.name, 'Canal 025000');

      expect(
        pageP95,
        lessThan(_budgetMs),
        reason:
            'Sin idx_channels_type_name, esto sería un scan+sort completo '
            'de 50k filas en cada página. p95 real: '
            '${pageP95.toStringAsFixed(2)} ms, presupuesto: $_budgetMs ms.',
      );
      expect(
        countP95,
        lessThan(_budgetMs),
        reason:
            'countChannels debe resolverse por índice, no por un scan '
            'completo. p95 real: ${countP95.toStringAsFixed(2)} ms, '
            'presupuesto: $_budgetMs ms.',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
