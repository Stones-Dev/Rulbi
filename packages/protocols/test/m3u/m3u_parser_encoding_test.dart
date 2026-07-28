import 'dart:io';

import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_protocols/src/m3u/m3u_core_parser.dart';
import 'package:test/test.dart';

const _expectedNames = [
  'La 1 (TVE) - España',
  'Antena 3 - Noticias',
  'Telecinco - Películas',
];

Future<List<Channel>> _parseFile(String path) async {
  final channels = <Channel>[];
  await for (final event in parseM3uCore(
    bytes: File(path).openRead(),
    sourceId: 's1',
  )) {
    if (event is M3uChannelBatch) channels.addAll(event.channels);
  }
  return channels;
}

void main() {
  group('parseM3uCore — encoding/EOL (T1.1 encoding_*.m3u)', () {
    test('decodifica UTF-8 con BOM y descarta el BOM de la primera línea', () async {
      final channels = await _parseFile(
        'test/fixtures/m3u/edge_cases/encoding_utf8_bom.m3u',
      );
      expect(channels.map((c) => c.name), _expectedNames);
    });

    test('decodifica Latin-1 sin BOM', () async {
      final channels = await _parseFile(
        'test/fixtures/m3u/edge_cases/encoding_latin1.m3u',
      );
      expect(channels.map((c) => c.name), _expectedNames);
    });

    test('decodifica UTF-16 con BOM (little-endian)', () async {
      final channels = await _parseFile(
        'test/fixtures/m3u/edge_cases/encoding_utf16.m3u',
      );
      expect(channels.map((c) => c.name), _expectedNames);
    });

    test('tolera CRLF/LF mixto sin fundir ni partir entradas', () async {
      final channels = await _parseFile(
        'test/fixtures/m3u/edge_cases/encoding_crlf_lf_mixed.m3u',
      );
      expect(channels.map((c) => c.name), _expectedNames);
      expect(channels.map((c) => c.tvgId), [
        'tve1.es',
        'antena3.es',
        'telecinco.es',
      ]);
    });
  });
}
