// player_spike — arnés A del spike S3 (libmpv vía media_kit).
//
// App de escritorio descartable, NO de producción (ver README.md). Reproduce
// el corpus de docs/bench/data/live_corpus.json + los fixtures VOD locales,
// registra hechos observables por entrada (arranque, buffering, pistas,
// seek, error) y exporta el resultado a
// docs/bench/data/media_kit_results.json para docs/bench/S3-desktop-spike.md.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

void main() {
  MediaKit.ensureInitialized();
  runApp(const SpikeApp());
}

class SpikeApp extends StatelessWidget {
  const SpikeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'player_spike — media_kit',
      home: const SpikeHomePage(),
    );
  }
}

class CorpusEntry {
  CorpusEntry({
    required this.id,
    required this.name,
    required this.uri,
    required this.category,
  });

  factory CorpusEntry.fromJson(Map<String, dynamic> json) => CorpusEntry(
    id: json['id'] as String,
    name: json['name'] as String,
    uri: json['url'] as String,
    category: json['category'] as String,
  );

  final String id;
  final String name;
  final String uri;
  final String category;
}

class EntryResult {
  EntryResult(this.entry);

  final CorpusEntry entry;
  bool reachedPlaying = false;
  int? msToFirstPlaying;
  int bufferingEvents = 0;
  int audioTrackCount = 0;
  int subtitleTrackCount = 0;
  double? durationSeconds;
  bool seekAttempted = false;
  bool seekSucceeded = false;
  String? error;
  bool timedOut = false;

  Map<String, dynamic> toJson() => {
    'id': entry.id,
    'name': entry.name,
    'category': entry.category,
    'reached_playing': reachedPlaying,
    'ms_to_first_playing': msToFirstPlaying,
    'buffering_events': bufferingEvents,
    'audio_track_count': audioTrackCount,
    'subtitle_track_count': subtitleTrackCount,
    'duration_seconds': durationSeconds,
    'seek_attempted': seekAttempted,
    'seek_succeeded': seekSucceeded,
    'timed_out': timedOut,
    'error': error,
  };
}

/// Repo root buscado subiendo desde el cwd hasta encontrar `melos.yaml`-like
/// marker (`pubspec.yaml` con `name: iptv_player`). Evita asumir que se
/// ejecuta siempre desde `packages/player_spike/`.
Directory _findRepoRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    final marker = File('${dir.path}/pubspec.yaml');
    if (marker.existsSync() &&
        marker.readAsStringSync().contains('name: iptv_player')) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  // Fallback razonable si no se encuentra (no debería pasar en este repo).
  return Directory.current;
}

List<CorpusEntry> _loadLiveCorpus(Directory repoRoot) {
  final file = File('${repoRoot.path}/docs/bench/data/live_corpus.json');
  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return (json['entries'] as List)
      .map((e) => CorpusEntry.fromJson(e as Map<String, dynamic>))
      .toList();
}

List<CorpusEntry> _localVodEntries(Directory repoRoot) {
  final fixturesDir = '${repoRoot.path}/docs/bench/data/fixtures';
  const files = <String, (String, String)>{
    'test1_baseline.mkv': ('VOD baseline', 'VOD (MPEG4.2/DivX + MP3)'),
    'test5_multi_audio_subs.mkv': (
      'VOD multi-audio + subs',
      'VOD (H264 + 2 audio + 7 subs)',
    ),
    'test7_damaged.mkv': (
      'VOD dañado (EBML junk)',
      'VOD formato rompedor',
    ),
    'test8_audio_gap.mkv': ('VOD audio gap', 'VOD estabilidad (gap)'),
  };
  final entries = <CorpusEntry>[];
  files.forEach((filename, meta) {
    final path = '$fixturesDir/$filename';
    if (File(path).existsSync()) {
      entries.add(
        CorpusEntry(
          id: filename,
          name: meta.$1,
          uri: path,
          category: meta.$2,
        ),
      );
    }
  });
  return entries;
}

class SpikeHomePage extends StatefulWidget {
  const SpikeHomePage({super.key});

  @override
  State<SpikeHomePage> createState() => _SpikeHomePageState();
}

class _SpikeHomePageState extends State<SpikeHomePage> {
  final List<String> _log = [];
  bool _running = false;

  @override
  void initState() {
    super.initState();
    // Autoarranque para poder correr el corpus completo con
    // `flutter run -d windows` sin interacción manual (medición no atendida
    // de C1/C5/C6). El botón sigue disponible para re-ejecuciones puntuales.
    WidgetsBinding.instance.addPostFrameCallback((_) => _runCorpus());
  }

  void _appendLog(String line) {
    setState(() => _log.add(line));
  }

  Future<void> _runCorpus() async {
    setState(() {
      _running = true;
      _log.clear();
    });

    final repoRoot = _findRepoRoot();
    final entries = [
      ..._loadLiveCorpus(repoRoot),
      ..._localVodEntries(repoRoot),
    ];
    final results = <EntryResult>[];

    for (final entry in entries) {
      _appendLog('▶ ${entry.id} (${entry.category})');
      final result = await _measureEntry(entry);
      results.add(result);
      _appendLog(
        '  playing=${result.reachedPlaying} '
        'ttfp=${result.msToFirstPlaying}ms '
        'audio=${result.audioTrackCount} subs=${result.subtitleTrackCount} '
        'seek=${result.seekSucceeded} error=${result.error ?? "-"}',
      );
    }

    final outFile = File(
      '${repoRoot.path}/docs/bench/data/media_kit_results.json',
    );
    outFile.parent.createSync(recursive: true);
    outFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'generated_by': 'packages/player_spike (arnés A, media_kit)',
        'media_kit_version': '1.2.6',
        'results': results.map((r) => r.toJson()).toList(),
      }),
    );
    _appendLog('\nEscrito ${outFile.path}');

    setState(() => _running = false);
  }

  Future<EntryResult> _measureEntry(CorpusEntry entry) async {
    final result = EntryResult(entry);
    final player = Player();
    final stopwatch = Stopwatch()..start();
    final completer = Completer<void>();
    late final List<StreamSubscription<void>> subs;

    void finish() {
      if (!completer.isCompleted) completer.complete();
    }

    subs = [
      player.stream.playing.listen((playing) {
        if (playing && !result.reachedPlaying) {
          result.reachedPlaying = true;
          result.msToFirstPlaying = stopwatch.elapsedMilliseconds;
        }
      }),
      player.stream.buffering.listen((buffering) {
        if (buffering) result.bufferingEvents++;
      }),
      player.stream.tracks.listen((tracks) {
        result.audioTrackCount = tracks.audio.length;
        result.subtitleTrackCount = tracks.subtitle.length;
      }),
      player.stream.duration.listen((d) {
        if (d.inMilliseconds > 0) {
          result.durationSeconds = d.inMilliseconds / 1000.0;
        }
      }),
      player.stream.error.listen((error) {
        result.error = error;
        finish();
      }),
    ];

    try {
      await player.open(Media(entry.uri), play: true);
      // Espera hasta 30s a que arranque o falle; si arranca, deja 5s más
      // para observar buffering/pistas y luego intenta un seek de prueba.
      await Future.any([
        completer.future,
        Future.delayed(const Duration(seconds: 30)),
      ]);

      if (result.reachedPlaying && result.error == null) {
        await Future.delayed(const Duration(seconds: 5));
        try {
          result.seekAttempted = true;
          await player.seek(const Duration(seconds: 2));
          await Future.delayed(const Duration(milliseconds: 500));
          result.seekSucceeded = player.state.position.inMilliseconds > 0;
        } catch (e) {
          result.seekSucceeded = false;
        }
      } else if (result.error == null) {
        result.timedOut = true;
      }
    } catch (e) {
      result.error = e.toString();
    } finally {
      for (final s in subs) {
        await s.cancel();
      }
      await player.dispose();
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('player_spike — arnés A (media_kit)')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ElevatedButton(
              onPressed: _running ? null : _runCorpus,
              child: Text(_running ? 'Ejecutando...' : 'Ejecutar corpus'),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: _log
                    .map(
                      (l) => Text(
                        l,
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
