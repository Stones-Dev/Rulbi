// tool/generate_bench_m3u.dart
//
// Genera el fixture de 100.000 canales para T1.5b (Benchmark 100k, RNF-01)
// a partir del catálogo real de iptv-org (`m3u/large/iptv_org_index.m3u`,
// 13.560 canales — ver tool/fetch_fixtures.dart). NO es sintético puro:
// preserva los dialectos, atributos heterogéneos y líneas descartables
// reales del catálogo, en vez de medir contra un M3U ideal.
//
// Método (documentado también en el plan de T1.5b y en
// packages/protocols/test/fixtures/m3u/README.md):
//   1. Agrupa el índice real en bloques por entrada (#EXTINF + directivas
//      intermedias opcionales + su línea de URL), con la misma lógica de
//      "primera línea no-# tras #EXTINF es la URL" que usa el parser real
//      (packages/protocols/lib/src/m3u/m3u_core_parser.dart) — así el
//      recuento de bloques coincide con lo que el parser real contará como
//      canales, no con un recuento ingenuo de líneas.
//   2. Emite 8 réplicas de esos bloques. La réplica 0 es el catálogo
//      original sin modificar. Las réplicas 1-7 sufijan `tvg-id` (o, si
//      falta, la URL) con `-rN` para que los ChannelRef derivados
//      (packages/core/lib/src/sync/channel_ref.dart, cascada
//      tvg-id → url → nombre) sean únicos entre réplicas — `channels` tiene
//      UNIQUE(sourceId, refKey) en packages/data, así que refs duplicados
//      abortarían el benchmark con una excepción en vez de medir un tiempo.
//   3. 8 réplicas dan 108.480 bloques; se truncan a exactamente 100.000,
//      siempre en un límite de bloque completo (nunca a mitad de entrada).
//
// El fichero de salida NO se commitea (gitignored junto a los demás
// fixtures de m3u/large/). Solo este generador vive en git.
//
// Uso (desde la raíz del repo):
//   dart run tool/fetch_fixtures.dart --only=iptv_org_index   # si falta
//   dart run tool/generate_bench_m3u.dart

import 'dart:io';

const _sourcePath = 'packages/protocols/test/fixtures/m3u/large/iptv_org_index.m3u';
const _destPath = 'packages/protocols/test/fixtures/m3u/large/bench_100k.m3u';
const _targetTotal = 100000;
const _replicaCount = 8;

final RegExp _tvgIdPattern = RegExp('tvg-id="([^"]*)"');

void main() {
  final source = File(_sourcePath);
  if (!source.existsSync()) {
    stderr.writeln(
      '$_sourcePath no existe — ejecuta primero:\n'
      '  dart run tool/fetch_fixtures.dart --only=iptv_org_index',
    );
    exitCode = 1;
    return;
  }

  final lines = source.readAsLinesSync();
  final blocks = _extractBlocks(lines);
  stdout.writeln('Índice real: ${blocks.length} bloques (#EXTINF) leídos de $_sourcePath.');

  if (blocks.length * _replicaCount < _targetTotal) {
    stderr.writeln(
      'El índice real (${blocks.length} canales) no alcanza para $_targetTotal '
      'con $_replicaCount réplicas (${blocks.length * _replicaCount} disponibles). '
      'Sube _replicaCount o revisa que el fixture descargado sea el completo.',
    );
    exitCode = 1;
    return;
  }

  final out = StringBuffer('#EXTM3U\n');
  final seenKeys = <String>{};
  var emitted = 0;

  outer:
  for (var r = 0; r < _replicaCount; r++) {
    for (final block in blocks) {
      if (emitted >= _targetTotal) break outer;
      final replicated = r == 0 ? block : _replicate(block, r);
      out.writeAll(replicated, '\n');
      out.write('\n');
      seenKeys.add(_dedupeKey(replicated, r));
      emitted++;
    }
  }

  File(_destPath).writeAsStringSync(out.toString());

  stdout.writeln('Escrito $_destPath: $emitted bloques.');
  stdout.writeln('Claves de dedupe únicas: ${seenKeys.length} (esperado: $emitted).');
  if (seenKeys.length != emitted) {
    stderr.writeln(
      'ALERTA: hay claves de dedupe repetidas — el benchmark fallaría por '
      'violación de UNIQUE(sourceId, refKey) en packages/data. Revisa '
      '_replicate() antes de usar este fixture.',
    );
    exitCode = 1;
  }
  if (emitted != _targetTotal) {
    stderr.writeln('ALERTA: se esperaban $_targetTotal bloques, se emitieron $emitted.');
    exitCode = 1;
  }
}

/// Agrupa líneas en bloques por entrada, replicando cómo
/// `m3u_core_parser.dart` decide qué es una entrada: cada bloque empieza en
/// una línea `#EXTINF:` e incluye toda línea siguiente hasta (sin incluir)
/// el próximo `#EXTINF:` o el fin de archivo. Líneas en blanco y la
/// cabecera `#EXTM3U` se descartan (el parser real también las ignora).
List<List<String>> _extractBlocks(List<String> lines) {
  final blocks = <List<String>>[];
  List<String>? current;

  for (final rawLine in lines) {
    final trimmed = rawLine.trim();
    if (trimmed.isEmpty) continue;
    if (trimmed.startsWith('#EXTM3U')) continue;

    if (trimmed.startsWith('#EXTINF:')) {
      if (current != null) blocks.add(current);
      current = [rawLine];
      continue;
    }

    current?.add(rawLine);
  }
  if (current != null) blocks.add(current);
  return blocks;
}

/// Devuelve una copia del bloque con `tvg-id` (si existe) y la URL primaria
/// sufijados con `-r$r`, más el nombre visible con un sufijo legible. Sufija
/// AMBOS tvg-id y URL (no solo el primero disponible) porque
/// `ChannelRef.derive` cae a la URL cuando `tvg-id` es nulo O vacío tras
/// trim — sufijar solo uno dejaría un agujero si algún bloque trae
/// `tvg-id=""`.
List<String> _replicate(List<String> block, int r) {
  final result = List<String>.of(block);

  // Línea #EXTINF: sufija tvg-id si el atributo existe, y el nombre visible
  // (heurística: después de la última coma de la línea — suficiente para un
  // generador de benchmark, no para parsing correcto general).
  final extinf = result[0];
  var newExtinf = extinf;
  final tvgMatch = _tvgIdPattern.firstMatch(extinf);
  // Solo sufija si el valor original es no vacío — `tvg-id=""` cuenta como
  // ausente para `ChannelRef.derive` (cae a la URL). Sufijar el vacío
  // produciría "-r$r" idéntico para todas las entradas sin tvg-id de la
  // misma réplica, exactamente la colisión que este generador debe evitar.
  if (tvgMatch != null && tvgMatch.group(1)!.trim().isNotEmpty) {
    newExtinf = newExtinf.replaceFirstMapped(
      _tvgIdPattern,
      (m) => 'tvg-id="${m.group(1)}-r$r"',
    );
  }
  final lastComma = newExtinf.lastIndexOf(',');
  if (lastComma >= 0) {
    newExtinf = '${newExtinf.substring(0, lastComma + 1)}'
        '${newExtinf.substring(lastComma + 1)} (r$r)';
  }
  result[0] = newExtinf;

  // Primera línea no-# tras el #EXTINF: es la URL real para el parser
  // (packages/protocols/lib/src/m3u/m3u_core_parser.dart). Se sufija su
  // segmento primario (antes de cualquier '|' de cabeceras/fallback Kodi)
  // con una query o fragmento, según ya tenga o no fragmento.
  for (var i = 1; i < result.length; i++) {
    final t = result[i].trim();
    if (t.startsWith('#')) continue;
    result[i] = _suffixUrlLine(result[i], r);
    break;
  }

  return result;
}

String _suffixUrlLine(String urlLine, int r) {
  final segments = urlLine.split('|');
  segments[0] = _suffixUrl(segments[0], r);
  return segments.join('|');
}

String _suffixUrl(String url, int r) {
  final hashIndex = url.indexOf('#');
  final base = hashIndex >= 0 ? url.substring(0, hashIndex) : url;
  final fragment = hashIndex >= 0 ? url.substring(hashIndex) : '';
  final sep = base.contains('?') ? '&' : '?';
  return '$base${sep}bench_r=$r$fragment';
}

/// Clave de unicidad aproximada para la verificación interna del generador
/// (no es exactamente `ChannelRef.derive`, no aplica `normalizeForMatching`
/// — solo comprueba que el generador no produjo colisiones evidentes).
String _dedupeKey(List<String> block, int r) {
  final tvgMatch = _tvgIdPattern.firstMatch(block[0]);
  final tvgId = tvgMatch?.group(1);
  if (tvgId != null && tvgId.trim().isNotEmpty) return 'sourceId::tvg:$tvgId';

  for (var i = 1; i < block.length; i++) {
    final t = block[i].trim();
    if (t.startsWith('#')) continue;
    return 'url:$t';
  }
  return 'name:${block[0]}';
}
