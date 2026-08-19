import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_protocols/src/xtream/xtream_client.dart';
import 'package:iptv_protocols/src/xtream/xtream_failure.dart';
import 'package:iptv_protocols/src/xtream/xtream_mapper.dart';
import 'package:iptv_protocols/src/xtream/xtream_vod.dart';
import 'package:test/test.dart';

import 'support/fake_xtream_transport.dart';

void main() {
  group('XtreamClient.vodStreams (fixture real: 1 película)', () {
    test('stream_id int, rating numérico, container_extension presente', () async {
      final client = _client(FakeXtreamTransport());

      final result = await client.vodStreams();

      final streams = (result as XtreamOk<List<XtreamVodStream>>).value;
      expect(streams, hasLength(1));
      final movie = streams.single;
      expect(movie.streamId, 1908388221);
      expect(movie.name, 'Pelicula de Prueba');
      expect(movie.containerExtension, 'mkv');
      expect(movie.rating, 7.5);
      expect(movie.categoryId, '2130693104');
    });
  });

  group('XtreamClient.vodInfo (fixture real: ficha completa)', () {
    test('aplana info + movie_data, tolera stream_id string aquí vs int en get_vod_streams', () async {
      final client = _client(FakeXtreamTransport());

      final result = await client.vodInfo('1908388221');

      final info = (result as XtreamOk<XtreamVodInfo>).value;
      expect(info.streamId, 1908388221, reason: 'movie_data.stream_id es string en este fixture, no int');
      expect(info.name, 'Pelicula de Prueba');
      expect(info.director, 'Director de Prueba');
      expect(info.cast, 'Actor Uno, Actor Dos');
      expect(info.genre, 'Drama, Prueba');
      expect(info.durationSecs, 5400);
      expect(info.rating, 7.5, reason: 'info.rating es string "7.5" en este fixture, se normaliza a double');
      expect(info.containerExtension, 'mkv');
      expect(
        info.backdropUrl,
        isNull,
        reason: 'fixture real trae backdrop_path: [null] — sin URL usable (S6.5, paso 7)',
      );
    });

    test('vod_id inválido (panel devuelve []) -> XtreamMalformed, no una ficha vacía inventada', () async {
      final fake = FakeXtreamTransport()..enqueue('get_vod_info', jsonResponse([]));
      final client = _client(fake);

      final result = await client.vodInfo('no-existe');

      expect((result as XtreamErr).failure, isA<XtreamMalformed>());
    });

    test('vod_id inválido (panel devuelve {}) -> XtreamMalformed', () async {
      final fake = FakeXtreamTransport()..enqueue('get_vod_info', jsonResponse({}));
      final client = _client(fake);

      final result = await client.vodInfo('no-existe');

      expect((result as XtreamErr).failure, isA<XtreamMalformed>());
    });
  });

  group('XtreamMapper.vodStreamToChannel', () {
    test('ChannelRef usa la forma canónica sin extensión, Channel.url la conserva', () {
      const stream = XtreamVodStream(
        streamId: 1908388221,
        name: 'Pelicula de Prueba',
        categoryId: '2130693104',
        containerExtension: 'mkv',
        rating: 7.5,
      );

      final channel = XtreamMapper.vodStreamToChannel(
        sourceId: 'src-1',
        stream: stream,
        categoryNames: {'2130693104': 'Peliculas'},
      );

      expect(channel.type, ContentType.vod);
      expect(channel.url.toString(), 'xtream://src-1/movie/1908388221.mkv');
      expect(
        channel.ref,
        ChannelRef.derive(sourceId: 'src-1', url: 'xtream://src-1/movie/1908388221', name: 'Pelicula de Prueba'),
        reason: 'el ref nunca lleva la extensión: un reetiquetado mkv->mp4 no debe romper el favorito',
      );
      expect(channel.metadata['x-xtream-container'], 'mkv');
      expect(channel.metadata['x-xtream-rating'], '7.5');
    });

    test('sin container_extension: canónica sin sufijo, sin lanzar', () {
      const stream = XtreamVodStream(streamId: 1, name: 'X', categoryId: null);
      final channel = XtreamMapper.vodStreamToChannel(sourceId: 'src-1', stream: stream);

      expect(channel.url.toString(), 'xtream://src-1/movie/1');
      expect(channel.categoryId, isNull);
    });
  });
}

XtreamClient _client(FakeXtreamTransport transport) => XtreamClient(
  host: Uri.parse('http://127.0.0.1:8081'),
  username: 'test',
  password: 'test',
  transport: transport,
);
