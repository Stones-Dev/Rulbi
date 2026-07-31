import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_protocols/src/xtream/xtream_client.dart';
import 'package:iptv_protocols/src/xtream/xtream_failure.dart';
import 'package:iptv_protocols/src/xtream/xtream_mapper.dart';
import 'package:iptv_protocols/src/xtream/xtream_series.dart';
import 'package:test/test.dart';

import 'support/fake_xtream_transport.dart';

void main() {
  group('XtreamClient.series (fixture real: 1 serie, sin episodios expandidos)', () {
    test('get_series no trae temporadas/episodios', () async {
      final client = _client(FakeXtreamTransport());

      final result = await client.series();

      final list = (result as XtreamOk<List<XtreamSeries>>).value;
      expect(list, hasLength(1));
      expect(list.single.seriesId, 115941465);
      expect(list.single.name, 'Serie de Prueba');
      expect(list.single.genre, 'Drama');
    });
  });

  group('XtreamClient.seriesInfo (fixture real: temporadas + episodios anidados)', () {
    test('1 temporada con 2 episodios, agrupados por la clave del mapa episodes', () async {
      final client = _client(FakeXtreamTransport());

      final result = await client.seriesInfo('115941465');

      final info = (result as XtreamOk<XtreamSeriesInfo>).value;
      expect(info.info.name, 'Serie de Prueba');
      expect(info.seasons, hasLength(1));
      expect(
        info.seasons.single.seasonNumber,
        0,
        reason: 'incoherencia real del fixture: seasons[0].season_number es 0',
      );
      expect(info.episodesBySeason.keys, [1], reason: 'la clave del mapa episodes es "1", no season_number');
      expect(info.episodesBySeason[1], hasLength(2));
      expect(info.episodesBySeason[1]!.first.id, '1875868768');
      expect(info.episodesBySeason[1]!.first.title, 'Episodio 1');
      expect(info.episodesBySeason[1]!.first.season, 1, reason: 'episode.season SÍ dice 1, distinto de season_number=0');
      expect(info.episodesBySeason[1]!.first.containerExtension, 'mp4');
    });

    test('series_id inválido (panel devuelve []) -> XtreamMalformed', () async {
      final fake = FakeXtreamTransport()..enqueue('get_series_info', jsonResponse([]));
      final client = _client(fake);

      final result = await client.seriesInfo('no-existe');

      expect((result as XtreamErr).failure, isA<XtreamMalformed>());
    });

    test('episodes como array plano (dialecto sintético) se reagrupa por episode.season', () async {
      final fake = FakeXtreamTransport()
        ..enqueue(
          'get_series_info',
          jsonResponse({
            'info': {'series_id': 1, 'name': 'Serie Plana'},
            'seasons': [],
            'episodes': [
              {'id': '10', 'episode_num': 1, 'title': 'E1', 'season': 1},
              {'id': '11', 'episode_num': 2, 'title': 'E2', 'season': 1},
              {'id': '20', 'episode_num': 1, 'title': 'E1 T2', 'season': 2},
            ],
          }),
        );
      final client = _client(fake);

      final result = await client.seriesInfo('1');

      final info = (result as XtreamOk<XtreamSeriesInfo>).value;
      expect(info.episodesBySeason[1], hasLength(2));
      expect(info.episodesBySeason[2], hasLength(1));
    });

    test('episodio sin season propio, dentro de episodes plano, cae en temporada 1', () async {
      final fake = FakeXtreamTransport()
        ..enqueue(
          'get_series_info',
          jsonResponse({
            'info': {'series_id': 1, 'name': 'Serie Sin Season'},
            'seasons': [],
            'episodes': [
              {'id': '10', 'episode_num': 1, 'title': 'E1'},
            ],
          }),
        );
      final client = _client(fake);

      final result = await client.seriesInfo('1');

      final info = (result as XtreamOk<XtreamSeriesInfo>).value;
      expect(info.episodesBySeason.keys, [1]);
    });
  });

  group('XtreamMapper.episodeToChannel', () {
    test('mapea un episodio bajo demanda, sin invocarse durante el import completo', () {
      const episode = XtreamEpisode(
        id: '1875868768',
        episodeNum: 1,
        title: 'Episodio 1',
        containerExtension: 'mp4',
        season: 1,
      );

      final channel = XtreamMapper.episodeToChannel(
        sourceId: 'src-1',
        seriesId: 115941465,
        seasonNumber: 1,
        episode: episode,
      );

      expect(channel.type, ContentType.series);
      expect(channel.url.toString(), 'xtream://src-1/series/1875868768.mp4');
      expect(channel.metadata['x-xtream-series-id'], '115941465');
      expect(channel.metadata['x-xtream-season'], '1');
      expect(channel.metadata['x-xtream-episode'], '1');
      expect(
        channel.ref,
        ChannelRef.derive(sourceId: 'src-1', url: 'xtream://src-1/series/1875868768', name: 'Episodio 1'),
      );
    });
  });
}

XtreamClient _client(FakeXtreamTransport transport) => XtreamClient(
  host: Uri.parse('http://127.0.0.1:8081'),
  username: 'test',
  password: 'test',
  transport: transport,
);
