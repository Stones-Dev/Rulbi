import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:iptv_protocols/iptv_protocols.dart';

import 'probe_result.dart';

/// Resumen del "Probar" del Formulario M3U (ui-spec §2.8): valida que la
/// URL/archivo responde y contiene un M3U parseable, sobre una **muestra**
/// (hasta [M3uProbe.defaultMaxBytes]) — no es la importación completa
/// (Ola 3, "UI de importación"), así que probar una lista de 100k
/// entradas no descarga la lista entera.
final class M3uProbeSummary {
  const M3uProbeSummary({required this.channelCount, required this.discardedCount});

  final int channelCount;
  final int discardedCount;

  @override
  String toString() =>
      'M3uProbeSummary(channels: $channelCount, discarded: $discardedCount)';
}

abstract interface class M3uProbe {
  Future<ProbeResult<M3uProbeSummary>> probeUrl(Uri url, {String? userAgent});
  Future<ProbeResult<M3uProbeSummary>> probeFile(String filePath);
}

/// Implementación real: `package:http` para la URL, `dart:io` para el
/// archivo local, y `parseM3u` (API pública de `packages/protocols`, P6 —
/// nunca el núcleo interno `parseM3uCore`) para interpretar la muestra.
final class HttpM3uProbe implements M3uProbe {
  HttpM3uProbe({
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
    this.maxBytes = defaultMaxBytes,
  }) : _client = client ?? http.Client();

  /// 256 KiB: de sobra para varias decenas/cientos de entradas de muestra
  /// en cualquier dialecto real observado en los fixtures de T1.1, sin
  /// acercarse al tamaño de una lista de 100k canales.
  static const int defaultMaxBytes = 256 * 1024;

  final http.Client _client;
  final Duration timeout;
  final int maxBytes;

  @override
  Future<ProbeResult<M3uProbeSummary>> probeUrl(
    Uri url, {
    String? userAgent,
  }) async {
    final http.Response response;
    try {
      final request = http.Request('GET', url);
      if (userAgent != null && userAgent.trim().isNotEmpty) {
        request.headers['User-Agent'] = userAgent.trim();
      }
      final streamed = await _client.send(request).timeout(timeout);
      response = await http.Response.fromStream(streamed).timeout(timeout);
    } on TimeoutException {
      return const ProbeFailed(ProbeFailureReason.timeout);
    } on SocketException {
      return const ProbeFailed(ProbeFailureReason.network);
    } on http.ClientException {
      return const ProbeFailed(ProbeFailureReason.network);
    }

    if (response.statusCode == 404) {
      return const ProbeFailed(ProbeFailureReason.notFound);
    }
    if (response.statusCode >= 400) {
      return const ProbeFailed(ProbeFailureReason.malformed);
    }

    final bytes = response.bodyBytes;
    return _parseSample(
      bytes.length > maxBytes ? bytes.sublist(0, maxBytes) : bytes,
    );
  }

  @override
  Future<ProbeResult<M3uProbeSummary>> probeFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return const ProbeFailed(ProbeFailureReason.notFound);
    }

    final List<int> bytes;
    try {
      final length = await file.length();
      if (length <= maxBytes) {
        bytes = await file.readAsBytes();
      } else {
        final handle = await file.open();
        try {
          bytes = await handle.read(maxBytes);
        } finally {
          await handle.close();
        }
      }
    } on FileSystemException {
      return const ProbeFailed(ProbeFailureReason.notFound);
    }

    return _parseSample(bytes);
  }

  Future<ProbeResult<M3uProbeSummary>> _parseSample(List<int> bytes) async {
    if (bytes.isEmpty) {
      return const ProbeFailed(ProbeFailureReason.malformed);
    }

    final outcome = parseM3u(bytes: Stream.value(bytes), sourceId: '_probe');
    var channelCount = 0;
    try {
      await for (final _ in outcome.channels) {
        channelCount++;
      }
    } catch (_) {
      return const ProbeFailed(ProbeFailureReason.malformed);
    }

    final report = await outcome.report;
    return ProbeOk(
      M3uProbeSummary(
        channelCount: channelCount,
        discardedCount: report.discarded.length,
      ),
    );
  }
}
