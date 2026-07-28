import 'dart:convert';
import 'dart:io';

import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_protocols/src/m3u/m3u_core_parser.dart';
import 'package:test/test.dart';

/// Ejecuta `parseM3uCore` sobre bytes en memoria y recoge canales +
/// descartes en listas planas, para aserciones simples en los tests.
Future<({List<Channel> channels, List<DiscardedLineInfo> discarded})>
_run(
  List<int> bytes, {
  String sourceId = 's1',
  int batchSize = 500,
}) async {
  final channels = <Channel>[];
  final discarded = <DiscardedLineInfo>[];
  await for (final event in parseM3uCore(
    bytes: Stream.value(bytes),
    sourceId: sourceId,
    batchSize: batchSize,
  )) {
    switch (event) {
      case M3uChannelBatch(channels: final batch):
        channels.addAll(batch);
      case M3uDiscard(:final line):
        discarded.add((lineNumber: line.lineNumber, reason: line.reason));
    }
  }
  return (channels: channels, discarded: discarded);
}

typedef DiscardedLineInfo = ({int lineNumber, String reason});

List<int> _bytesOfFile(String relativePath) =>
    File(relativePath).readAsBytesSync();

void main() {
  group('parseM3uCore — real fixture pequeño', () {
    test('parsea las 3 entradas de es_samsung.m3u', () async {
      final result = await _run(
        _bytesOfFile('test/fixtures/m3u/real/iptv_org_es_samsung.m3u'),
        sourceId: 'src-es-samsung',
      );

      expect(result.discarded, isEmpty);
      expect(result.channels, hasLength(3));

      final first = result.channels.first;
      expect(first.name, 'People are Awesome');
      expect(first.tvgId, 'PeopleAreAwesome.us@SD');
      expect(
        first.url,
        Uri.parse(
          'https://jukin-peopleareawesome-2-es.samsung.wurl.tv/playlist.m3u8',
        ),
      );
      expect(
        first.ref,
        ChannelRef.derive(
          sourceId: 'src-es-samsung',
          tvgId: 'PeopleAreAwesome.us@SD',
          url: first.url.toString(),
          name: first.name,
        ),
      );
    });

    test('respeta el orden de entrada de los canales', () async {
      final result = await _run(
        _bytesOfFile('test/fixtures/m3u/real/iptv_org_es_samsung.m3u'),
      );
      expect(result.channels.map((c) => c.name), [
        'People are Awesome',
        'The Pet Collective',
        'Trace Sport Stars (1080p) [Geo-blocked]',
      ]);
    });
  });

  group('parseM3uCore — group-title y Category.derive', () {
    test('deriva categoryId de forma determinista desde group-title', () async {
      const m3u = '#EXTM3U\n'
          '#EXTINF:-1 tvg-id="a" group-title="Noticias",Canal A\n'
          'https://example.com/a.m3u8\n'
          '#EXTINF:-1 tvg-id="b" group-title="NOTICIAS",Canal B\n'
          'https://example.com/b.m3u8\n';
      final result = await _run(utf8.encode(m3u), sourceId: 's1');

      expect(result.channels, hasLength(2));
      expect(result.channels[0].categoryId, result.channels[1].categoryId);
      expect(
        result.channels[0].categoryId,
        Category.derive(
          sourceId: 's1',
          type: ContentType.live,
          name: 'Noticias',
        ).id,
      );
      // group-title también se conserva crudo en metadata.
      expect(result.channels[0].metadata['group-title'], 'Noticias');
    });

    test('categoryId es null si no hay group-title', () async {
      const m3u = '#EXTM3U\n#EXTINF:-1,Canal Sin Categoria\nhttps://example.com/x.m3u8\n';
      final result = await _run(utf8.encode(m3u));
      expect(result.channels.single.categoryId, isNull);
    });
  });

  group('parseM3uCore — descartes (P7: nunca excepción)', () {
    test('descarta y reporta una URL sin #EXTINF previo', () async {
      const m3u = '#EXTM3U\nhttps://example.com/huerfana.m3u8\n'
          '#EXTINF:-1,Canal Bueno\nhttps://example.com/bueno.m3u8\n';
      final result = await _run(utf8.encode(m3u));

      expect(result.channels, hasLength(1));
      expect(result.channels.single.name, 'Canal Bueno');
      expect(result.discarded, hasLength(1));
      expect(result.discarded.single.reason, 'URL sin #EXTINF previo');
      expect(result.discarded.single.lineNumber, 2);
    });

    test('descarta y reporta un #EXTINF colgado antes de la siguiente entrada', () async {
      const m3u = '#EXTM3U\n'
          '#EXTINF:-1,Colgado\n'
          '#EXTINF:-1,Canal Bueno\n'
          'https://example.com/bueno.m3u8\n';
      final result = await _run(utf8.encode(m3u));

      expect(result.channels, hasLength(1));
      expect(result.channels.single.name, 'Canal Bueno');
      expect(result.discarded, hasLength(1));
      expect(
        result.discarded.single.reason,
        '#EXTINF sin URL antes de la siguiente entrada',
      );
    });

    test('descarta y reporta un #EXTINF colgado antes de fin de archivo', () async {
      const m3u = '#EXTM3U\n#EXTINF:-1,Colgado Al Final\n';
      final result = await _run(utf8.encode(m3u));

      expect(result.channels, isEmpty);
      expect(result.discarded, hasLength(1));
      expect(
        result.discarded.single.reason,
        '#EXTINF sin URL antes de fin de archivo',
      );
    });
  });

  group('parseM3uCore — lotes', () {
    test('emite en lotes de batchSize, no canal a canal', () async {
      final buffer = StringBuffer('#EXTM3U\n');
      for (var i = 0; i < 7; i++) {
        buffer.writeln('#EXTINF:-1,Canal $i');
        buffer.writeln('https://example.com/$i.m3u8');
      }

      final batches = <int>[];
      await for (final event in parseM3uCore(
        bytes: Stream.value(utf8.encode(buffer.toString())),
        sourceId: 's1',
        batchSize: 3,
      )) {
        if (event is M3uChannelBatch) batches.add(event.channels.length);
      }

      // 7 canales con batchSize=3 -> lotes de 3, 3 y 1 (nunca 7 lotes de 1).
      expect(batches, [3, 3, 1]);
    });
  });
}
