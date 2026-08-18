import 'xtream_json.dart';
import 'xtream_stream.dart';

/// Una película cruda de `get_vod_streams` (listado). `get_vod_info`
/// (ficha completa) es [XtreamVodInfo], acción aparte.
final class XtreamVodStream {
  const XtreamVodStream({
    required this.streamId,
    required this.name,
    required this.categoryId,
    this.streamIcon,
    this.containerExtension,
    this.rating,
    this.directSourceHost,
  });

  final int streamId;
  final String name;
  final String? categoryId;
  final String? streamIcon;

  /// Ausente en algún dialecto sintético cubierto en T1.4 (paneles que no
  /// lo declaran hasta `get_vod_info`) — `XtreamUrlResolver` tolera
  /// `null` (canónica sin sufijo de extensión).
  final String? containerExtension;

  /// Número (`7.5`) en este fixture; string (`"0.0"`) en `get_vod_info`
  /// del mismo panel — dialecto real de T1.1, normalizado aquí con
  /// [asFlexibleDouble].
  final double? rating;

  /// `direct_source` saneado a solo su host (ADR-006/P5) — nunca la URL
  /// completa, donde viajarían credenciales propias del CDN.
  final String? directSourceHost;

  static XtreamVodStream fromJson(Map<String, Object?> json) => XtreamVodStream(
    streamId: asFlexibleInt(json['stream_id']),
    name: asFlexibleString(json['name']) ?? '',
    categoryId: asFlexibleString(json['category_id']),
    streamIcon: nonEmptyOrNull(asFlexibleString(json['stream_icon'])),
    containerExtension: nonEmptyOrNull(asFlexibleString(json['container_extension'])),
    rating: asFlexibleDouble(json['rating']),
    directSourceHost: sanitizedDirectSourceHost(asFlexibleString(json['direct_source'])),
  );

  @override
  String toString() => 'XtreamVodStream($streamId, $name)';
}

/// Ficha completa de `get_vod_info`: el fixture real trae dos objetos
/// anidados (`info` con los metadatos editoriales, `movie_data` con los
/// campos de listado repetidos) — se aplanan aquí en un único DTO. El
/// dialecto real más notable (T1.1): `movie_data.stream_id` es **string**
/// aquí, mientras que el mismo campo es **int** en `get_vod_streams` —
/// mismo panel, mismo campo, dos tipos distintos.
final class XtreamVodInfo {
  const XtreamVodInfo({
    required this.streamId,
    required this.name,
    this.categoryId,
    this.containerExtension,
    this.plot,
    this.director,
    this.cast,
    this.genre,
    this.releaseDate,
    this.coverUrl,
    this.backdropUrl,
    this.durationSecs,
    this.rating,
  });

  final int streamId;
  final String name;
  final String? categoryId;
  final String? containerExtension;
  final String? plot;
  final String? director;
  final String? cast;
  final String? genre;
  final String? releaseDate;
  final String? coverUrl;

  /// Primera URL de `info.backdrop_path` (S6.5, paso 7 — hero a sangre del
  /// detalle VOD, frame Figma `43:2`). `null` si el panel no lo trae —
  /// `DetailHero` cae entonces a [coverUrl] difuminado.
  final String? backdropUrl;
  final int? durationSecs;
  final double? rating;

  static XtreamVodInfo fromJson(Map<String, Object?> json) {
    final info = asFlexibleMap(json['info']);
    final movieData = asFlexibleMap(json['movie_data']);

    return XtreamVodInfo(
      streamId: asFlexibleInt(movieData['stream_id']),
      name: asFlexibleString(movieData['name']) ?? asFlexibleString(info['name']) ?? '',
      categoryId: asFlexibleString(movieData['category_id']),
      containerExtension: nonEmptyOrNull(asFlexibleString(movieData['container_extension'])),
      // `plot`/`description` y `cast`/`actors` son sinónimos reales que
      // distintos paneles usan indistintamente para el mismo dato.
      plot: nonEmptyOrNull(asFlexibleString(info['plot']) ?? asFlexibleString(info['description'])),
      director: nonEmptyOrNull(asFlexibleString(info['director'])),
      cast: nonEmptyOrNull(asFlexibleString(info['cast']) ?? asFlexibleString(info['actors'])),
      genre: nonEmptyOrNull(asFlexibleString(info['genre'])),
      releaseDate: nonEmptyOrNull(
        asFlexibleString(info['releasedate']) ?? asFlexibleString(info['releaseDate']),
      ),
      coverUrl: nonEmptyOrNull(
        asFlexibleString(info['cover_big']) ?? asFlexibleString(info['movie_image']),
      ),
      backdropUrl: asFlexibleFirstUrl(info['backdrop_path']),
      durationSecs: asFlexibleIntOrNull(info['duration_secs']),
      rating: asFlexibleDouble(info['rating']),
    );
  }

  @override
  String toString() => 'XtreamVodInfo($streamId, $name)';
}
