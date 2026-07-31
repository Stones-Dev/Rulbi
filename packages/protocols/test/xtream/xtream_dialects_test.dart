import 'package:iptv_protocols/src/xtream/xtream_json.dart';
import 'package:iptv_protocols/src/xtream/xtream_series.dart';
import 'package:iptv_protocols/src/xtream/xtream_stream.dart';
import 'package:iptv_protocols/src/xtream/xtream_vod.dart';
import 'package:test/test.dart';

/// T1.4: un test por anomalía de dialecto Xtream. Las primeras son
/// **reales, observadas en los propios fixtures de T1.1** (mismo panel,
/// mismo campo, dos formas distintas según la action); las últimas son
/// sintéticas, documentadas como tales.
void main() {
  group('Dialectos reales (observados en fixtures de T1.1)', () {
    test('stream_id: int en get_vod_streams, string en get_vod_info.movie_data', () {
      final fromStreams = XtreamVodStream.fromJson({'stream_id': 1908388221, 'name': 'X'});
      final fromInfo = XtreamVodInfo.fromJson({
        'info': {'name': 'X'},
        'movie_data': {'stream_id': '1908388221'},
      });

      expect(fromStreams.streamId, 1908388221);
      expect(fromInfo.streamId, 1908388221);
    });

    test('rating: número en get_vod_streams, string en get_vod_info', () {
      final fromStreams = XtreamVodStream.fromJson({'stream_id': 1, 'name': 'X', 'rating': 7.5});
      final fromInfo = XtreamVodInfo.fromJson({
        'info': {'name': 'X', 'rating': '7.5'},
        'movie_data': {'stream_id': 1},
      });

      expect(fromStreams.rating, 7.5);
      expect(fromInfo.rating, 7.5);
    });

    test('stream_icon: URL, null, ausente y "" son formas equivalentes de "sin icono"', () {
      final conUrl = XtreamLiveStream.fromJson({
        'stream_id': 1,
        'name': 'X',
        'stream_icon': 'https://example.com/x.png',
      });
      final conNull = XtreamLiveStream.fromJson({'stream_id': 1, 'name': 'X', 'stream_icon': null});
      final ausente = XtreamLiveStream.fromJson({'stream_id': 1, 'name': 'X'});
      final vacio = XtreamLiveStream.fromJson({'stream_id': 1, 'name': 'X', 'stream_icon': ''});

      expect(conUrl.streamIcon, 'https://example.com/x.png');
      expect(conNull.streamIcon, isNull);
      expect(ausente.streamIcon, isNull);
      expect(vacio.streamIcon, isNull);
    });

    test('category_id string + category_ids array de ints no rompe el parseo', () {
      final stream = XtreamLiveStream.fromJson({
        'stream_id': 1,
        'name': 'X',
        'category_id': '1544024662',
        'category_ids': [1544024662, 999],
      });

      expect(stream.categoryId, '1544024662');
    });

    test('overview/cover/youtube_trailer null no rompen XtreamSeason/XtreamSeries', () {
      final season = XtreamSeason.fromJson({
        'id': 1,
        'season_number': 0,
        'name': 'Temporada 1',
        'overview': null,
        'cover': null,
        'cover_big': null,
      });
      final series = XtreamSeries.fromJson({
        'series_id': 1,
        'name': 'X',
        'cover': null,
        'youtube_trailer': null,
      });

      expect(season.overview, isNull);
      expect(season.coverUrl, isNull);
      expect(series.coverUrl, isNull);
    });

    test('backdrop_path: [] y [null] no rompen el parseo (campo no modelado)', () {
      expect(
        () => XtreamSeries.fromJson({'series_id': 1, 'name': 'X', 'backdrop_path': <Object?>[]}),
        returnsNormally,
      );
      expect(
        () => XtreamSeries.fromJson({'series_id': 1, 'name': 'X', 'backdrop_path': <Object?>[null]}),
        returnsNormally,
      );
    });

    test('direct_source vacío ("") -> sin host saneado', () {
      expect(sanitizedDirectSourceHost(''), isNull);
      expect(sanitizedDirectSourceHost(null), isNull);
    });

    test('direct_source con URL real -> se conserva solo el host, nunca ruta/query', () {
      final host = sanitizedDirectSourceHost('http://cdn.example.com:8080/live/user/pass/1.ts?token=abc');
      expect(host, 'cdn.example.com');
    });

    test('direct_source con texto que no es una URL reconocible -> null, no lanza', () {
      expect(sanitizedDirectSourceHost('no es una url'), isNull);
    });
  });

  group('Dialectos sintéticos', () {
    test('container_extension ausente -> null, sin lanzar (canónica sin sufijo la maneja el mapper)', () {
      final stream = XtreamVodStream.fromJson({'stream_id': 1, 'name': 'X'});
      expect(stream.containerExtension, isNull);
    });

    test('num como string en vez de int no rompe (campo no modelado pero presente en el JSON)', () {
      expect(
        () => XtreamLiveStream.fromJson({'stream_id': 1, 'name': 'X', 'num': '1'}),
        returnsNormally,
      );
    });

    test('asFlexibleInt tolera string, double y bool para el mismo campo lógico', () {
      expect(asFlexibleInt('5'), 5);
      expect(asFlexibleInt(5.0), 5);
      expect(asFlexibleInt(true), 1);
      expect(asFlexibleInt('no-numero', fallback: -1), -1);
    });

    test('un campo completamente desconocido y nuevo se ignora sin romper ningún fromJson', () {
      expect(
        () => XtreamLiveStream.fromJson({
          'stream_id': 1,
          'name': 'X',
          'un_campo_que_no_existia_en_2026': {'anidado': true},
        }),
        returnsNormally,
      );
      expect(
        () => XtreamVodStream.fromJson({'stream_id': 1, 'name': 'X', 'campo_futuro': 42}),
        returnsNormally,
      );
      expect(
        () => XtreamSeriesInfo.fromJson({
          'info': {'series_id': 1, 'name': 'X'},
          'seasons': [],
          'episodes': {},
          'campo_futuro_del_panel': 'lo que sea',
        }),
        returnsNormally,
      );
    });
  });
}
