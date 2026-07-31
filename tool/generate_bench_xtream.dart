// tool/generate_bench_xtream.dart
//
// Genera el fixture sintético de 50.000 live streams para el benchmark de
// sanity de T1.4 (packages/protocols/test/xtream/xtream_benchmark_test.dart).
// A diferencia de tool/generate_bench_m3u.dart (que replica el catálogo REAL
// de iptv-org), aquí no existe un catálogo Xtream real de ese tamaño para
// replicar — los únicos datos reales de T1.1 son 2 canales
// (o0Zz/xtreamcodeserver, servidor de prueba local). Es sintético puro,
// documentado como tal (mismo espíritu que packages/protocols/test/fixtures/
// xtream/synthetic/README.md).
//
// Distribuido en 20 categorías (2.500 canales/categoría) para que el
// benchmark también ejercite `XtreamMapper.liveStreamToChannel` con un mapa
// de categorías no trivial. 1 de cada 7 canales sin `stream_icon` (`null`),
// 1 de cada 11 sin `epg_channel_id` (cae al fallback de ChannelRef vía la
// URL canónica) — variedad realista, no un dataset artificialmente uniforme.
//
// El fichero de salida NO se commitea (gitignored, ver .gitignore). Solo
// este generador vive en git.
//
// Uso (desde la raíz del repo):
//   dart run tool/generate_bench_xtream.dart

import 'dart:convert';
import 'dart:io';

const _destPath = 'packages/protocols/test/fixtures/xtream/large/bench_50k_live_streams.json';
const _targetTotal = 50000;
const _categoryCount = 20;

void main() {
  final streams = <Map<String, Object?>>[];

  for (var i = 0; i < _targetTotal; i++) {
    final streamId = 1000000 + i;
    final categoryIndex = i % _categoryCount;
    final withoutIcon = i % 7 == 0;
    final withoutEpg = i % 11 == 0;

    streams.add({
      'num': i + 1,
      'name': 'Canal Bench $i',
      'stream_type': 'live',
      'stream_id': streamId,
      'stream_icon': withoutIcon ? null : 'https://example.invalid/logos/$streamId.png',
      'added': '0',
      'is_adult': '0',
      'category_id': '${100 + categoryIndex}',
      'category_ids': [100 + categoryIndex],
      'custom_sid': null,
      'direct_source': '',
      'epg_channel_id': withoutEpg ? '' : 'bench$i.test',
      'tv_archive': i % 5 == 0 ? 1 : 0,
      'tv_archive_duration': i % 5 == 0 ? 7 : 0,
    });
  }

  File(_destPath).writeAsStringSync(jsonEncode(streams));

  stdout.writeln('Escrito $_destPath: ${streams.length} live streams sintéticos.');
  stdout.writeln('Tamaño: ${(File(_destPath).lengthSync() / (1024 * 1024)).toStringAsFixed(1)} MB.');
}
