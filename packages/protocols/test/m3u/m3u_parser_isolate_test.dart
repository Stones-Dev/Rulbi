import 'dart:convert';
import 'dart:io';

import 'package:iptv_protocols/iptv_protocols.dart';
import 'package:test/test.dart';

/// Tests de la API pública `parseM3u` (el wrapper de isolate real, a
/// diferencia de `parseM3uCore` que testean el resto de ficheros de este
/// directorio). Pocos tests a propósito: la lógica de parseo ya está
/// cubierta exhaustivamente contra `parseM3uCore` sin isolate; aquí solo
/// se verifica que el relé isolate↔isolate no pierde ni corrompe nada.
void main() {
  group('parseM3u (wrapper de isolate)', () {
    test('produce los mismos canales que el núcleo, vía isolate real', () async {
      final outcome = parseM3u(
        bytes: File(
          'test/fixtures/m3u/real/iptv_org_es_samsung.m3u',
        ).openRead(),
        sourceId: 'iso-1',
      );

      final channels = await outcome.channels.toList();
      final report = await outcome.report;

      expect(channels, hasLength(3));
      expect(channels.map((c) => c.name), [
        'People are Awesome',
        'The Pet Collective',
        'Trace Sport Stars (1080p) [Geo-blocked]',
      ]);
      expect(report.parsed, 3);
      expect(report.discarded, isEmpty);
    });

    test('el informe de descartes llega completo tras drenar el stream', () async {
      const m3u = '#EXTM3U\n'
          'https://huerfana.example.com/x.m3u8\n'
          '#EXTINF:-1,Canal Bueno\n'
          'https://example.com/bueno.m3u8\n';
      final outcome = parseM3u(
        bytes: Stream.value(utf8.encode(m3u)),
        sourceId: 's1',
      );

      final channels = await outcome.channels.toList();
      final report = await outcome.report;

      expect(channels, hasLength(1));
      expect(report.parsed, 1);
      expect(report.discarded, hasLength(1));
      expect(report.discarded.single.reason, 'URL sin #EXTINF previo');
    });

    test('no spawnea nada si nadie escucha el stream de canales', () async {
      // Solo construir el M3uParseOutcome (sin escuchar channels ni
      // esperar report) no debe lanzar ni bloquear el test — el
      // isolate.spawn está diferido a onListen.
      final outcome = parseM3u(
        bytes: Stream.value(utf8.encode('#EXTM3U\n')),
        sourceId: 's1',
      );
      expect(outcome, isNotNull);
      // No se espera outcome.report aquí a propósito: nunca se resolvería
      // sin un listener en outcome.channels, y eso es el comportamiento
      // correcto (diseño "onListen diferido").
    });
  });
}
