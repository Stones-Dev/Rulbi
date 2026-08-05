import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:iptv_app/features/sources/m3u_probe.dart';
import 'package:iptv_app/features/sources/probe_result.dart';
import 'package:test/test.dart';

/// S4 · Ola 2 (Formulario M3U, ui-spec §2.8). Sin red real ni disco real
/// más allá de un archivo temporal — mismo criterio de aislamiento que
/// los tests de `HttpXtreamTransport`/`XtreamClient` en `packages/protocols`.
void main() {
  const sampleM3u = '#EXTM3U\n'
      '#EXTINF:-1 tvg-id="ch1" group-title="News",Channel One\n'
      'http://example.com/ch1.ts\n'
      '#EXTINF:-1 tvg-id="ch2" group-title="News",Channel Two\n'
      'http://example.com/ch2.ts\n';

  group('HttpM3uProbe.probeUrl', () {
    test('200 con M3U válido: cuenta los canales de la muestra', () async {
      final client = MockClient(
        (request) async => http.Response(sampleM3u, 200),
      );
      final probe = HttpM3uProbe(client: client);

      final result = await probe.probeUrl(Uri.parse('http://host/list.m3u'));

      expect(result, isA<ProbeOk<M3uProbeSummary>>());
      final summary = (result as ProbeOk<M3uProbeSummary>).value;
      expect(summary.channelCount, 2);
      expect(summary.discardedCount, 0);
    });

    test('envía el User-Agent cuando se pasa uno', () async {
      String? capturedUserAgent;
      final client = MockClient((request) async {
        capturedUserAgent = request.headers['User-Agent'];
        return http.Response(sampleM3u, 200);
      });
      final probe = HttpM3uProbe(client: client);

      await probe.probeUrl(
        Uri.parse('http://host/list.m3u'),
        userAgent: 'MiAgente/1.0',
      );

      expect(capturedUserAgent, 'MiAgente/1.0');
    });

    test('404: ProbeFailureReason.notFound', () async {
      final client = MockClient((request) async => http.Response('', 404));
      final probe = HttpM3uProbe(client: client);

      final result = await probe.probeUrl(Uri.parse('http://host/list.m3u'));

      expect(result, isA<ProbeFailed<M3uProbeSummary>>());
      expect(
        (result as ProbeFailed<M3uProbeSummary>).reason,
        ProbeFailureReason.notFound,
      );
    });

    test('500: ProbeFailureReason.malformed', () async {
      final client = MockClient((request) async => http.Response('', 500));
      final probe = HttpM3uProbe(client: client);

      final result = await probe.probeUrl(Uri.parse('http://host/list.m3u'));

      expect(
        (result as ProbeFailed<M3uProbeSummary>).reason,
        ProbeFailureReason.malformed,
      );
    });

    test('cuerpo vacío: ProbeFailureReason.malformed', () async {
      final client = MockClient((request) async => http.Response('', 200));
      final probe = HttpM3uProbe(client: client);

      final result = await probe.probeUrl(Uri.parse('http://host/list.m3u'));

      expect(
        (result as ProbeFailed<M3uProbeSummary>).reason,
        ProbeFailureReason.malformed,
      );
    });

    test('excepción de socket: ProbeFailureReason.network', () async {
      final client = MockClient(
        (request) async => throw const SocketException('conexión rechazada'),
      );
      final probe = HttpM3uProbe(client: client);

      final result = await probe.probeUrl(Uri.parse('http://host/list.m3u'));

      expect(
        (result as ProbeFailed<M3uProbeSummary>).reason,
        ProbeFailureReason.network,
      );
    });

    test('timeout: ProbeFailureReason.timeout', () async {
      final client = MockClient((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return http.Response(sampleM3u, 200);
      });
      final probe = HttpM3uProbe(
        client: client,
        timeout: const Duration(milliseconds: 1),
      );

      final result = await probe.probeUrl(Uri.parse('http://host/list.m3u'));

      expect(
        (result as ProbeFailed<M3uProbeSummary>).reason,
        ProbeFailureReason.timeout,
      );
    });
  });

  group('HttpM3uProbe.probeFile', () {
    test('archivo existente con M3U válido: cuenta los canales', () async {
      final dir = await Directory.systemTemp.createTemp('m3u_probe_test');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/list.m3u');
      await file.writeAsString(sampleM3u, encoding: utf8);

      final probe = HttpM3uProbe();
      final result = await probe.probeFile(file.path);

      expect((result as ProbeOk<M3uProbeSummary>).value.channelCount, 2);
    });

    test('archivo inexistente: ProbeFailureReason.notFound', () async {
      final probe = HttpM3uProbe();

      final result = await probe.probeFile(
        'C:/ruta/que/no/existe/nunca.m3u',
      );

      expect(
        (result as ProbeFailed<M3uProbeSummary>).reason,
        ProbeFailureReason.notFound,
      );
    });
  });
}
