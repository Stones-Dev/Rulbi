@Tags(['benchmark'])
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_data/iptv_data.dart';

/// Micro-benchmark **sintético** de la capa de BD (T1.5): 100k filas
/// generadas, escritura por lotes en transacción + reindexado FTS +
/// una búsqueda, para validar que el diseño de índices aguanta RNF-01.
///
/// **No es** el benchmark real de la tarea "Benchmark 100k" (Notion,
/// bloqueada): ese mide la importación de extremo a extremo — parser
/// M3U real incluido (T1.2, bloqueado en T1.1) — y sigue pendiente. Este
/// test es evidencia de que el esquema no es el cuello de botella; no
/// cierra esa tarea.
void main() {
  test(
    '100k canales: inserción por lotes + búsqueda FTS5 en tiempos razonables',
    () async {
      final db = IptvDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      const total = 100000;
      final channels = DriftChannelRepository(db);

      final insertStopwatch = Stopwatch()..start();
      await channels.replaceSourceContent(
        's1',
        Stream.fromIterable(
          Iterable.generate(
            total,
            (i) => Channel(
              ref: ChannelRef(sourceId: 's1', key: 'canal-$i'),
              sourceId: 's1',
              type: ContentType.live,
              // Un España cada 1000 para poder medir la búsqueda con un
              // resultado pequeño y realista, no todo el dataset.
              name: i % 1000 == 0 ? 'España $i' : 'Canal $i',
              url: Uri.parse('http://example.com/$i'),
            ),
          ),
        ),
      );
      insertStopwatch.stop();

      final searchStopwatch = Stopwatch()..start();
      final results = await channels.search('espana', limit: total);
      searchStopwatch.stop();

      expect(results, hasLength(total ~/ 1000));

      // Presupuestos generosos (P1 habla de <30s de principio a fin
      // *con* el parser real; aquí solo la capa de BD, en memoria, sin
      // parsing): si esto se dispara muy por encima, el esquema/índices
      // son sospechosos antes que el parser que aún no existe.
      expect(
        insertStopwatch.elapsedMilliseconds,
        lessThan(20000),
        reason:
            'Inserción de 100k canales demasiado lenta: ${insertStopwatch.elapsedMilliseconds} ms',
      );
      expect(
        searchStopwatch.elapsedMilliseconds,
        lessThan(1000),
        reason:
            'Búsqueda FTS5 demasiado lenta: ${searchStopwatch.elapsedMilliseconds} ms',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
