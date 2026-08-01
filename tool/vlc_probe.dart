// tool/vlc_probe.dart
//
// Arnés B del spike S3 (libVLC como motor, medido vía CLI — ver
// docs/bench/S3-desktop-spike.md, C3: no existe binding Flutter de
// escritorio mantenido para libVLC, así que se mide el motor directamente,
// no un plugin). Reproduce el mismo corpus que el arnés A
// (docs/bench/data/live_corpus.json + fixtures VOD locales) contra
// `vlc.exe --intf dummy --play-and-exit`, parsea el log verboso de VLC y
// exporta el mismo tipo de hechos observables a
// docs/bench/data/vlc_results.json.
//
// Requiere VLC portable descomprimido en docs/bench/data/tools/vlc-3.0.23/
// (docs/bench/S3-desktop-spike.md documenta la descarga y verificación
// SHA-256 contra get.videolan.org). No se descarga automáticamente aquí
// para no repetir la verificación de integridad fuera del reporte.
//
// Uso:
//   dart run tool/vlc_probe.dart

import 'dart:convert';
import 'dart:io';

class CorpusEntry {
  CorpusEntry({required this.id, required this.name, required this.category, required this.uri});

  factory CorpusEntry.fromJson(Map<String, dynamic> json) => CorpusEntry(
    id: json['id'] as String,
    name: json['name'] as String,
    category: json['category'] as String,
    uri: json['url'] as String,
  );

  final String id;
  final String name;
  final String category;
  final String uri;
}

class VlcResult {
  VlcResult(this.entry);

  final CorpusEntry entry;
  bool reachedPlaying = false;
  int? msToFirstPlaying;
  int audioTrackCount = 0;
  int subtitleTrackCount = 0;
  bool timedOut = false;
  int? exitCode;
  String? error;

  Map<String, dynamic> toJson() => {
    'id': entry.id,
    'name': entry.name,
    'category': entry.category,
    'reached_playing': reachedPlaying,
    'ms_to_first_playing': msToFirstPlaying,
    'audio_track_count': audioTrackCount,
    'subtitle_track_count': subtitleTrackCount,
    'timed_out': timedOut,
    'exit_code': exitCode,
    'error': error,
  };
}

Future<void> main(List<String> args) async {
  final repoRoot = Directory.current;
  final vlcExe = File(
    '${repoRoot.path}/docs/bench/data/tools/vlc-3.0.23/vlc.exe',
  );
  if (!vlcExe.existsSync()) {
    stderr.writeln(
      'No se encuentra ${vlcExe.path}.\n'
      'Descarga y descomprime el VLC portable oficial primero (ver '
      'docs/bench/S3-desktop-spike.md, sección C2/arnés B) — no se hace '
      'automáticamente para no saltarse la verificación SHA-256 manual.',
    );
    exitCode = 1;
    return;
  }

  final corpusFile = File(
    '${repoRoot.path}/docs/bench/data/live_corpus.json',
  );
  final corpusJson =
      jsonDecode(corpusFile.readAsStringSync()) as Map<String, dynamic>;
  final liveEntries = (corpusJson['entries'] as List)
      .map((e) => CorpusEntry.fromJson(e as Map<String, dynamic>))
      .toList();

  final fixturesDir = Directory('${repoRoot.path}/docs/bench/data/fixtures');
  final vodEntries = <CorpusEntry>[];
  const vodMeta = <String, (String, String)>{
    'test1_baseline.mkv': ('VOD baseline', 'VOD (MPEG4.2/DivX + MP3)'),
    'test5_multi_audio_subs.mkv': (
      'VOD multi-audio + subs',
      'VOD (H264 + 2 audio + 7 subs)',
    ),
    'test7_damaged.mkv': ('VOD dañado (EBML junk)', 'VOD formato rompedor'),
    'test8_audio_gap.mkv': ('VOD audio gap', 'VOD estabilidad (gap)'),
  };
  vodMeta.forEach((filename, meta) {
    final f = File('${fixturesDir.path}/$filename');
    if (f.existsSync()) {
      vodEntries.add(
        CorpusEntry(id: filename, name: meta.$1, category: meta.$2, uri: f.path),
      );
    }
  });

  final entries = [...liveEntries, ...vodEntries];
  final results = <VlcResult>[];
  final logDir = Directory('${repoRoot.path}/docs/bench/data/vlc_logs');
  logDir.createSync(recursive: true);

  for (final entry in entries) {
    stdout.writeln('▶ ${entry.id} (${entry.category})');
    final result = await _probeEntry(vlcExe, entry, logDir);
    results.add(result);
    stdout.writeln(
      '  playing=${result.reachedPlaying} ttfp=${result.msToFirstPlaying}ms '
      'audio=${result.audioTrackCount} subs=${result.subtitleTrackCount} '
      'exit=${result.exitCode} error=${result.error ?? "-"}',
    );
  }

  final outFile = File('${repoRoot.path}/docs/bench/data/vlc_results.json');
  outFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'generated_by': 'tool/vlc_probe.dart (arnés B, VLC CLI)',
      'vlc_version': '3.0.23-win64 (get.videolan.org, oficial)',
      'results': results.map((r) => r.toJson()).toList(),
    }),
  );
  stdout.writeln('\nEscrito ${outFile.path}');
}

Future<VlcResult> _probeEntry(
  File vlcExe,
  CorpusEntry entry,
  Directory logDir,
) async {
  final result = VlcResult(entry);
  final logFile = File('${logDir.path}/${entry.id}.log');
  final stopwatch = Stopwatch()..start();

  Process process;
  try {
    process = await Process.start(vlcExe.path, [
      '--intf', 'dummy',
      '--play-and-exit',
      '--run-time=30',
      '--no-video-title-show',
      '-vvv',
      entry.uri,
    ], runInShell: false);
  } catch (e) {
    result.error = 'No se pudo lanzar vlc.exe: $e';
    return result;
  }

  final logBuffer = StringBuffer();
  final playingRe = RegExp(r'core (input|es).*(Buffering|start).*', caseSensitive: false);
  final audioTrackRe = RegExp(r'Track\s+\d+.*audio', caseSensitive: false);
  final subTrackRe = RegExp(r'Track\s+\d+.*(subtitle|spu)', caseSensitive: false);

  void handleLine(String line) {
    logBuffer.writeln(line);
    if (!result.reachedPlaying &&
        (line.contains('Buffering') || line.contains('using audio decoder') ||
            line.contains('using video decoder') || playingRe.hasMatch(line))) {
      result.reachedPlaying = true;
      result.msToFirstPlaying = stopwatch.elapsedMilliseconds;
    }
    if (audioTrackRe.hasMatch(line)) result.audioTrackCount++;
    if (subTrackRe.hasMatch(line)) result.subtitleTrackCount++;
  }

  process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(handleLine);
  process.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen(handleLine);

  try {
    result.exitCode = await process.exitCode.timeout(
      const Duration(seconds: 40),
      onTimeout: () {
        result.timedOut = true;
        process.kill();
        return -1;
      },
    );
  } catch (e) {
    result.error = e.toString();
  }

  logFile.writeAsStringSync(logBuffer.toString());
  return result;
}
