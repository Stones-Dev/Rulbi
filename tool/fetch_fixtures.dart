// tool/fetch_fixtures.dart
//
// Descarga bajo demanda los golden files "grandes" de T1.1 que
// deliberadamente NO se commitean (packages/protocols/test/fixtures/*/README.md
// explica el porqué de cada uno: benchmark T1.5b y prueba de estrés del
// parser XMLTV). Lee tool/fixtures_manifest.json, descarga cada entrada y
// verifica su SHA-256 contra el manifest.
//
// Uso:
//   dart run tool/fetch_fixtures.dart              # descarga todo lo que falte
//   dart run tool/fetch_fixtures.dart --only=<id>  # descarga solo una entrada
//   dart run tool/fetch_fixtures.dart --force      # redescarga aunque ya exista
//
// Se ejecuta desde la raíz del repo (usa rutas relativas del manifest).

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

class FixtureEntry {
  FixtureEntry({
    required this.id,
    required this.url,
    required this.dest,
    required this.sha256,
    required this.note,
  });

  factory FixtureEntry.fromJson(Map<String, dynamic> json) => FixtureEntry(
    id: json['id'] as String,
    url: json['url'] as String,
    dest: json['dest'] as String,
    sha256: json['sha256'] as String?,
    note: json['note'] as String? ?? '',
  );

  final String id;
  final String url;
  final String dest;
  final String? sha256;
  final String note;
}

Future<void> main(List<String> args) async {
  final only = _argValue(args, '--only');
  final force = args.contains('--force');

  final manifestFile = File('tool/fixtures_manifest.json');
  if (!manifestFile.existsSync()) {
    stderr.writeln(
      'No se encuentra tool/fixtures_manifest.json. '
      '¿Estás ejecutando esto desde la raíz del repo?',
    );
    exitCode = 1;
    return;
  }

  final manifestJson =
      jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
  final entries = (manifestJson['fixtures'] as List)
      .map((e) => FixtureEntry.fromJson(e as Map<String, dynamic>))
      .toList();

  final selected = only == null
      ? entries
      : entries.where((e) => e.id == only).toList();

  if (selected.isEmpty) {
    stderr.writeln('Ninguna fixture coincide con --only=$only.');
    exitCode = 1;
    return;
  }

  var failures = 0;
  for (final entry in selected) {
    final ok = await _fetchAndVerify(entry, force: force);
    if (!ok) failures++;
  }

  if (failures > 0) {
    stderr.writeln('\n$failures fixture(s) fallaron. Ver mensajes arriba.');
    exitCode = 1;
  } else {
    stdout.writeln('\nTodo OK: ${selected.length} fixture(s) verificadas.');
  }
}

Future<bool> _fetchAndVerify(FixtureEntry entry, {required bool force}) async {
  final destFile = File(entry.dest);

  if (destFile.existsSync() && !force) {
    stdout.writeln('${entry.id}: ya existe, verificando hash existente...');
    final existingHash = await _sha256Of(destFile);
    if (entry.sha256 != null && existingHash == entry.sha256) {
      stdout.writeln('${entry.id}: OK (hash coincide, no se redescarga).');
      return true;
    }
    stdout.writeln(
      '${entry.id}: hash NO coincide (o no había hash registrado) — redescargando.',
    );
  }

  stdout.writeln('${entry.id}: descargando de ${entry.url} ...');
  destFile.parent.createSync(recursive: true);

  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(entry.url));
    final response = await request.close();
    if (response.statusCode != 200) {
      stderr.writeln(
        '${entry.id}: HTTP ${response.statusCode} al descargar ${entry.url}.',
      );
      return false;
    }

    final sink = destFile.openWrite();
    await response.pipe(sink);
  } finally {
    client.close();
  }

  final downloadedHash = await _sha256Of(destFile);
  if (entry.sha256 == null) {
    stdout.writeln(
      '${entry.id}: descargado (${_humanSize(destFile.lengthSync())}). '
      'AVISO: el manifest no tiene sha256 registrado todavía — '
      'hash calculado: $downloadedHash. Añádelo a tool/fixtures_manifest.json '
      'tras verificar manualmente que el contenido es correcto.',
    );
    return true;
  }

  if (downloadedHash != entry.sha256) {
    stderr.writeln(
      '${entry.id}: SHA-256 NO COINCIDE.\n'
      '  esperado: ${entry.sha256}\n'
      '  obtenido: $downloadedHash\n'
      '  El fichero se ha dejado en disco para inspección manual: ${entry.dest}',
    );
    return false;
  }

  stdout.writeln(
    '${entry.id}: OK (${_humanSize(destFile.lengthSync())}, hash verificado).',
  );
  return true;
}

Future<String> _sha256Of(File file) async {
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString();
}

String _humanSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String? _argValue(List<String> args, String prefix) {
  for (final arg in args) {
    if (arg.startsWith('$prefix=')) {
      return arg.substring(prefix.length + 1);
    }
  }
  return null;
}
