import 'dart:convert';
import 'dart:io';

import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_protocols/src/m3u/m3u_core_parser.dart';
import 'package:test/test.dart';

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

const _dir = 'test/fixtures/m3u/edge_cases';

void main() {
  group('parseM3uCore — dialectos (T1.1 edge_cases/)', () {
    test('extvlcopt_user_agent: #EXTVLCOPT entre #EXTINF y la URL', () async {
      final channels = await _parseFile('$_dir/extvlcopt_user_agent.m3u');

      expect(channels, hasLength(1));
      final channel = channels.single;
      expect(channel.name, 'Channel One');
      expect(channel.tvgId, 'Channel1.us');
      expect(channel.metadata['group-title'], 'News');
      expect(
        channel.metadata['x-vlcopt-http-user-agent'],
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
      );
      expect(
        channel.metadata['x-vlcopt-http-referrer'],
        'https://example.com/',
      );
      expect(channel.metadata['x-vlcopt-http-origin'], 'https://example.com/');
    });

    test('kodiprop_drm_single_key: DRM clearkey de una sola clave', () async {
      final channels = await _parseFile('$_dir/kodiprop_drm_single_key.m3u');

      expect(channels, hasLength(1));
      final channel = channels.single;
      expect(channel.name, 'name1');
      expect(channel.metadata['x-vlcopt-http-user-agent'], 'Android');
      expect(
        channel.metadata['x-kodiprop-inputstreamaddon'],
        'inputstream.adaptive',
      );
      expect(
        channel.metadata['x-kodiprop-inputstream.adaptive.manifest_type'],
        'dash',
      );
      expect(
        channel.metadata['x-kodiprop-inputstream.adaptive.license_type'],
        'clearkey',
      );
      expect(
        channel.metadata['x-kodiprop-inputstream.adaptive.license_key'],
        'a18b6aa739be4c0b114605fcfb5d6b68:b41c3a6f7511b2e3a828d9580124c89d',
      );
      // tvg-logo="" (vacío) no debe producir un Uri "vacío" espurio.
      expect(channel.logo, isNull);
    });

    test('kodiprop_drm_multi_key: DRM clearkey de varias claves', () async {
      final channels = await _parseFile('$_dir/kodiprop_drm_multi_key.m3u');

      expect(channels, hasLength(1));
      final channel = channels.single;
      expect(channel.name, 'name2');
      expect(
        channel.metadata['x-kodiprop-inputstream.adaptive.license_key'],
        '{15965a6dbafd12c4af6aca127b271d5b:23dd40b93306de23ec667fb17a61fd3,'
            '88a3f1c2b6e04d7a9c5f3e2d1a0b9c8e:71f4e2d9c8b7a6958473625140302f1e,'
            'ac3b9d8e7f6a5b4c3d2e1f0a9b8c7d6e:d4c3b2a190f8e7d6c5b4a392817065f4}',
      );
    });

    test(
      'pipe_user_agent_referer: sintaxis Kodi URL|clave=valor&clave=valor',
      () async {
        // El fixture reproduce el ejemplo LITERAL del issue #57, que trae
        // un solo #EXTINF seguido de dos líneas de URL — M3U estrictamente
        // mal formado (cada entrada necesita su propio #EXTINF). El
        // comportamiento correcto y honesto es: la primera URL cierra el
        // #EXTINF abierto; la segunda, al no tener #EXTINF propio, se
        // descarta y se reporta — no se le inventa una identidad de canal.
        final channels = <Channel>[];
        final discardReasons = <String>[];
        await for (final event in parseM3uCore(
          bytes: File('$_dir/pipe_user_agent_referer.m3u').openRead(),
          sourceId: 's1',
        )) {
          switch (event) {
            case M3uChannelBatch(channels: final batch):
              channels.addAll(batch);
            case M3uDiscard(:final line):
              discardReasons.add(line.reason);
          }
        }

        expect(channels, hasLength(1));
        final channel = channels.single;
        expect(
          channel.url,
          Uri.parse('https://www.streamaway.net/fra/13e/mono.m3u8'),
        );
        expect(channel.metadata['x-http-user-agent'], 'Mozilla/5.0');
        expect(
          channel.metadata['x-http-referrer'],
          'https://www.streamaway.net/fr/13erue-fr.php',
        );

        expect(discardReasons, ['URL sin #EXTINF previo']);
      },
    );

    test(
      'pipe suffix con un solo parámetro (Referer, sin User-Agent)',
      () async {
        // Complementa el test anterior: el fixture en disco no puede
        // ejercitar esta rama con un #EXTINF propio (es el ejemplo mal
        // formado literal del issue), así que se verifica aquí con un M3U
        // sintético bien formado — el mismo patrón `URL|Referer=...` que
        // la segunda línea del fixture, pero con su propio #EXTINF.
        const m3u = '#EXTM3U\n'
            '#EXTINF:0,Solo Referer\n'
            'https://www.streamaway.net/fra/histo/index.m3u8|Referer=https://www.streamaway.net/fr/Histoire-fr.php\n';
        final channels = <Channel>[];
        await for (final event in parseM3uCore(
          bytes: Stream.value(utf8.encode(m3u)),
          sourceId: 's1',
        )) {
          if (event is M3uChannelBatch) channels.addAll(event.channels);
        }

        expect(channels, hasLength(1));
        final channel = channels.single;
        expect(channel.metadata.containsKey('x-http-user-agent'), isFalse);
        expect(
          channel.metadata['x-http-referrer'],
          'https://www.streamaway.net/fr/Histoire-fr.php',
        );
      },
    );
  });
}
