// tool/select_spike_corpus.dart
//
// Selecciona de forma reproducible 8-10 URLs live variadas de los golden
// files reales de T1.1 (packages/protocols/test/fixtures/m3u/real/) para
// el spike de S3 (libmpv/media_kit vs libVLC). La selección no es a ojo:
// cada entrada tiene una razón documentada de por qué representa una
// categoría distinta (códec, contenedor, geo-bloqueo, audio-only...).
//
// Uso:
//   dart run tool/select_spike_corpus.dart
//
// Escribe docs/bench/data/live_corpus.json (URLs + metadata) para que los
// arneses A (media_kit) y B (VLC CLI) del spike lean la misma lista.

import 'dart:convert';
import 'dart:io';

class CorpusEntry {
  const CorpusEntry({
    required this.id,
    required this.name,
    required this.url,
    required this.category,
    required this.sourceFixture,
    required this.note,
  });

  final String id;
  final String name;
  final String url;
  final String category;
  final String sourceFixture;
  final String note;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'category': category,
    'source_fixture': sourceFixture,
    'note': note,
  };
}

// Selección fija y documentada (no aleatoria): cada entrada cubre una
// categoría de C1 que el consenso de cierre de S2 pidió explícitamente.
// Extraídas a mano de los fixtures reales ya comiteados en el repo —
// dart run recorre el fixture solo para verificar que la línea sigue
// existiendo tal cual (detecta drift del fixture), no para "descubrir"
// la lista en caliente.
const _entries = [
  CorpusEntry(
    id: 'de_ard_hls_h264_hd',
    name: 'Das Erste HD',
    url: 'https://daserste-live.ard-mcdn.de/daserste/live/hls/de/master.m3u8',
    category: 'HLS h264 HD (broadcaster público, alta disponibilidad esperada)',
    sourceFixture: 'kodinerds_clean_tv.m3u',
    note: 'Caso "debería funcionar siempre": ARD es broadcaster público alemán.',
  ),
  CorpusEntry(
    id: 'de_zdf_hls_h264_hd',
    name: 'ZDF HD',
    url: 'https://zdf-hls-15.akamaized.net/hls/live/2016498/de/veryhigh/master.m3u8',
    category: 'HLS h264 HD, CDN Akamai',
    sourceFixture: 'kodinerds_clean_tv.m3u',
    note: 'Segundo broadcaster público, CDN distinto (Akamai vs ard-mcdn).',
  ),
  CorpusEntry(
    id: 'sk_rtvs_hevc',
    name: ':Šport (1080p)',
    url: 'http://88.212.15.27/live/test_rtvs_sport_hevc/playlist.m3u8',
    category: 'HLS h265/HEVC explícito (nombre del stream lo declara)',
    sourceFixture: 'iptv_org_sports.m3u',
    note: 'Único candidato h265 detectado por nombre en los fixtures reales.',
  ),
  CorpusEntry(
    id: 'us_pluto_smil',
    name: '3ABN English',
    url:
        'https://3abn.bozztv.com/3abn2/3abn_live/smil:3abn_live.smil/playlist.m3u8',
    category: 'HLS con URL de tipo SMIL en el path (dialecto no estándar)',
    sourceFixture: 'iptv_org_us.m3u',
    note: 'El segmento "smil:...smil" en la URL no es un patrón HLS habitual.',
  ),
  CorpusEntry(
    id: 'fr_geo_blocked',
    name: 'Trace Sport Stars (1080p) [Geo-blocked]',
    url:
        'http://tracesportstars-samsunges.amagi.tv/hls/amagi_hls_data_samsunguk-tracesport-samsungspain/CDN/playlist.m3u8',
    category: 'HLS geo-bloqueado (marcado explícitamente en el propio EXTINF)',
    sourceFixture: 'iptv_org_es_samsung.m3u',
    note:
        'Caso de error esperado: geo-block, no debería confundirse con fallo del motor.',
  ),
  CorpusEntry(
    id: 'es_radio_icecast',
    name: 'Flaix 93.8',
    url: 'https://streaming.giraweb.com/8020/stream',
    category: 'Audio-only (icecast/shoutcast), sin contenedor HLS',
    sourceFixture: 'iprd_all_stations.m3u',
    note: 'Radio pura: valida el camino de audio-only de ambos motores.',
  ),
  CorpusEntry(
    id: 'ad_radio_raw_ts_port',
    name: 'Pròxima 94.6',
    url: 'http://91.187.93.115:8000/;stream/1',
    category: 'URL con path atípico (";stream/1") sobre HTTP plano, IP directa',
    sourceFixture: 'iprd_all_stations.m3u',
    note: 'IP directa sin DNS, sin TLS, path con punto y coma — dialecto raro.',
  ),
  CorpusEntry(
    id: 'fr_direct_ip_hls',
    name: '6ter (1080p)',
    url: 'http://145.239.5.177/314/index.m3u8',
    category: 'HLS servido por IP directa (sin DNS), sin TLS',
    sourceFixture: 'iptv_org_fr.m3u',
    note: 'Contraste con el patrón "hostname+CDN" del resto del corpus.',
  ),
  CorpusEntry(
    id: 'orange_dash_expired',
    name: 'Classic FM (Orange DASH)',
    url:
        'https://vo-live-media.cdb.cdn.orange.com/Content/Channel/classic_fm/DASH/master.mpd?expires=1734441066&md5=5yiYwF9LCSpOygMQKBr-IQ',
    category: 'DASH (.mpd) con URL firmada — casi seguro caducada (expires=...)',
    sourceFixture: 'iprd_all_stations.m3u',
    note:
        'Caso de "muerte por caducidad de firma", distinto de 404/timeout '
        'sintéticos de C6: valida cómo reacciona cada motor a un enlace '
        'que devuelve error de autenticación/expiración real, no inventado.',
  ),
];

Future<void> main(List<String> args) async {
  final repoRoot = Directory.current.path;
  final missing = <String>[];

  for (final entry in _entries) {
    final fixturePath =
        'packages/protocols/test/fixtures/m3u/real/${entry.sourceFixture}';
    final file = File(fixturePath);
    if (!file.existsSync()) {
      missing.add('${entry.id}: fixture no encontrado ($fixturePath)');
      continue;
    }
    final content = file.readAsStringSync();
    if (!content.contains(entry.url)) {
      missing.add(
        '${entry.id}: la URL ya no aparece literal en $fixturePath '
        '(el fixture ha cambiado desde que se seleccionó esta entrada)',
      );
    }
  }

  if (missing.isNotEmpty) {
    stderr.writeln('Drift detectado en el corpus fijo del spike:');
    for (final m in missing) {
      stderr.writeln('  - $m');
    }
    stderr.writeln(
      'Revisa tool/select_spike_corpus.dart y actualiza las entradas '
      'afectadas antes de continuar.',
    );
    exitCode = 1;
    return;
  }

  final outDir = Directory('docs/bench/data');
  if (!outDir.existsSync()) {
    outDir.createSync(recursive: true);
  }
  final outFile = File('docs/bench/data/live_corpus.json');
  final json = const JsonEncoder.withIndent('  ').convert({
    'generated_by': 'tool/select_spike_corpus.dart',
    'repo_root': repoRoot,
    'entries': _entries.map((e) => e.toJson()).toList(),
  });
  outFile.writeAsStringSync(json);
  stdout.writeln(
    'OK: ${_entries.length} entradas verificadas contra sus fixtures. '
    'Escrito ${outFile.path}',
  );
}
