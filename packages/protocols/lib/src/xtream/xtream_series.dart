import 'xtream_json.dart';
import 'xtream_stream.dart';

/// Una serie cruda de `get_series` (listado) — **sin** temporadas ni
/// episodios: esa estructura solo llega con `get_series_info` (ficha
/// completa, [XtreamSeriesInfo]), una acción aparte por serie. Un import
/// completo no puede pedir `get_series_info` de las 5.000 series de un
/// panel grande (N+1 de red) — se pide bajo demanda al abrir la ficha
/// (decisión de T1.4, ver plan).
final class XtreamSeries {
  const XtreamSeries({
    required this.seriesId,
    required this.name,
    this.categoryId,
    this.plot,
    this.cast,
    this.director,
    this.genre,
    this.releaseDate,
    this.coverUrl,
    this.rating,
  });

  final int seriesId;
  final String name;
  final String? categoryId;
  final String? plot;
  final String? cast;
  final String? director;
  final String? genre;
  final String? releaseDate;
  final String? coverUrl;
  final double? rating;

  static XtreamSeries fromJson(Map<String, Object?> json) => XtreamSeries(
    seriesId: asFlexibleInt(json['series_id']),
    name: asFlexibleString(json['name']) ?? '',
    categoryId: asFlexibleString(json['category_id']),
    plot: nonEmptyOrNull(asFlexibleString(json['plot'])),
    cast: nonEmptyOrNull(asFlexibleString(json['cast'])),
    director: nonEmptyOrNull(asFlexibleString(json['director'])),
    genre: nonEmptyOrNull(asFlexibleString(json['genre'])),
    releaseDate: nonEmptyOrNull(
      asFlexibleString(json['releaseDate']) ?? asFlexibleString(json['releasedate']),
    ),
    coverUrl: nonEmptyOrNull(asFlexibleString(json['cover'])),
    rating: asFlexibleDouble(json['rating']),
  );

  @override
  String toString() => 'XtreamSeries($seriesId, $name)';
}

/// Metadatos de una temporada, tal como aparecen en `seasons` de
/// `get_series_info`. **No** es la fuente de verdad para agrupar
/// episodios — el fixture real de T1.1 trae `season_number: 0` en la
/// única temporada mientras sus episodios declaran `season: 1` (la misma
/// serie, el mismo panel). La agrupación real la hace la *clave* del mapa
/// `episodes` (ver [XtreamSeriesInfo.episodesBySeason]); `seasons` solo
/// aporta el nombre/resumen/portada de ficha para esa temporada.
final class XtreamSeason {
  const XtreamSeason({
    required this.id,
    required this.seasonNumber,
    required this.name,
    this.episodeCount,
    this.overview,
    this.coverUrl,
  });

  final int id;
  final int seasonNumber;
  final String name;
  final int? episodeCount;
  final String? overview;
  final String? coverUrl;

  static XtreamSeason fromJson(Map<String, Object?> json) => XtreamSeason(
    id: asFlexibleInt(json['id']),
    seasonNumber: asFlexibleInt(json['season_number']),
    name: asFlexibleString(json['name']) ?? '',
    episodeCount: asFlexibleIntOrNull(json['episode_count']),
    overview: nonEmptyOrNull(asFlexibleString(json['overview'])),
    coverUrl: nonEmptyOrNull(asFlexibleString(json['cover_big']) ?? asFlexibleString(json['cover'])),
  );

  @override
  String toString() => 'XtreamSeason($seasonNumber, $name)';
}

/// Un episodio de `episodes` dentro de `get_series_info`. `id` se
/// conserva como `String` (el fixture real lo manda así, `"1875868768"`)
/// — es el identificador que alimenta la URL canónica de reproducción
/// (ADR-006), no un contador.
final class XtreamEpisode {
  const XtreamEpisode({
    required this.id,
    required this.episodeNum,
    required this.title,
    this.containerExtension,
    this.durationSecs,
    this.season,
    this.stillUrl,
  });

  final String id;
  final int episodeNum;
  final String title;
  final String? containerExtension;
  final int? durationSecs;

  /// `season` propio del episodio — puede no coincidir con
  /// `XtreamSeason.seasonNumber` de la temporada que lo contiene (ver
  /// nota de [XtreamSeason]). Se conserva tal cual, sin intentar
  /// reconciliarlo.
  final int? season;

  /// Miniatura del episodio (`info.movie_image`, S6.5 — la pide el frame
  /// canónico de Detalle Serie fusionado en Figma). Muchos paneles no la
  /// rellenan: el propio fixture real de T1.1 la trae a `null` en sus 2
  /// episodios — la UI debe tener un fallback para ese caso, no asumir que
  /// siempre hay miniatura.
  final String? stillUrl;

  static XtreamEpisode fromJson(Map<String, Object?> json) {
    final info = asFlexibleMap(json['info']);
    return XtreamEpisode(
      id: asFlexibleString(json['id']) ?? '',
      episodeNum: asFlexibleInt(json['episode_num']),
      title: asFlexibleString(json['title']) ?? '',
      containerExtension: nonEmptyOrNull(asFlexibleString(json['container_extension'])),
      durationSecs: asFlexibleIntOrNull(info['duration_secs']),
      season: asFlexibleIntOrNull(json['season']),
      stillUrl: nonEmptyOrNull(asFlexibleString(info['movie_image'])),
    );
  }

  @override
  String toString() => 'XtreamEpisode($id, S${season ?? "?"}E$episodeNum, $title)';
}

/// Ficha completa de `get_series_info`: `info` (metadatos editoriales,
/// misma forma que [XtreamSeries]), `seasons` (metadatos de ficha por
/// temporada) y `episodes` — un mapa `{"<temporada>": [episodios]}` en la
/// forma documentada de la API, pero tolerado también como **array
/// plano** (dialecto sintético cubierto en T1.4: algún panel de terceros
/// no anida por temporada). En ese caso se reagrupa por
/// [XtreamEpisode.season] (o `1` si el propio episodio tampoco lo trae).
final class XtreamSeriesInfo {
  const XtreamSeriesInfo({
    required this.info,
    required this.seasons,
    required this.episodesBySeason,
  });

  final XtreamSeries info;
  final List<XtreamSeason> seasons;

  /// Clave = número de temporada tal como aparece en `episodes` (la
  /// fuente de verdad para agrupar, no `seasons[].season_number`).
  final Map<int, List<XtreamEpisode>> episodesBySeason;

  static XtreamSeriesInfo fromJson(Map<String, Object?> json) {
    final info = XtreamSeries.fromJson(asFlexibleMap(json['info']));
    final seasons = [
      for (final s in asFlexibleList(json['seasons']))
        if (s is Map) XtreamSeason.fromJson(asFlexibleMap(s)),
    ];

    final episodesBySeason = <int, List<XtreamEpisode>>{};
    final episodesRaw = json['episodes'];
    if (episodesRaw is Map) {
      episodesRaw.forEach((key, value) {
        final seasonKey = int.tryParse(key.toString()) ?? 0;
        episodesBySeason[seasonKey] = [
          for (final e in asFlexibleList(value))
            if (e is Map) XtreamEpisode.fromJson(asFlexibleMap(e)),
        ];
      });
    } else if (episodesRaw is List) {
      for (final e in episodesRaw) {
        if (e is! Map) continue;
        final episode = XtreamEpisode.fromJson(asFlexibleMap(e));
        final seasonKey = episode.season ?? 1;
        episodesBySeason.putIfAbsent(seasonKey, () => []).add(episode);
      }
    }

    return XtreamSeriesInfo(info: info, seasons: seasons, episodesBySeason: episodesBySeason);
  }

  @override
  String toString() =>
      'XtreamSeriesInfo(${info.name}, ${seasons.length} temporadas de ficha, '
      '${episodesBySeason.length} temporadas con episodios)';
}
