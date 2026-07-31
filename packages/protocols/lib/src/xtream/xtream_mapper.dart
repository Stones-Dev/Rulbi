import 'package:iptv_core/iptv_core.dart';

import 'xtream_category.dart';
import 'xtream_series.dart';
import 'xtream_stream.dart';
import 'xtream_url_resolver.dart';
import 'xtream_vod.dart';

/// Conversión de DTOs de protocolo Xtream a entidades de `core` — el único
/// sitio del cliente que conoce `sourceId` y las reglas de derivación
/// (`Category.derive`, `ChannelRef.derive`, `XtreamUrlResolver`) que
/// `core` ya define para M3U y que ADR-006 extiende a Xtream. Funciones
/// puras y estáticas: se testean sin red ni cliente, reutilizadas por
/// `XtreamClient.importChannels()` (T1.4, bloque de import) y por
/// cualquier código que solo necesite mapear un DTO ya obtenido (p. ej.
/// una categoría sola en la UI).
final class XtreamMapper {
  const XtreamMapper._();

  /// Categoría cruda → `core.Category`. Igual que
  /// `Category.derive` ya hace para `group-title` de M3U: dos
  /// dispositivos que importan el mismo panel deben derivar el mismo id
  /// de categoría sin coordinarse entre sí, así que el id final no es el
  /// `category_id` crudo de Xtream (que es estable dentro de un panel
  /// pero no tiene por qué serlo entre dos capturas del mismo panel si el
  /// operador reordena categorías) sino el derivado por nombre.
  static Category categoryToCore({
    required String sourceId,
    required XtreamCategory category,
    required ContentType type,
    int order = 0,
  }) => Category.derive(sourceId: sourceId, type: type, name: category.name, order: order);

  /// Canal live crudo → `core.Channel`. `categoryNames` es el mapa
  /// `category_id` crudo → nombre, construido a partir de una llamada
  /// previa a `liveCategories()` — Xtream no manda el nombre de la
  /// categoría dentro de `get_live_streams`, solo su id (a diferencia de
  /// M3U, donde `group-title` ya trae el nombre en la propia línea). Sin
  /// mapa (o id ausente del mapa), se degrada al `category_id` crudo como
  /// nombre en vez de perder la categoría — mejor una categoría con un id
  /// numérico visible que ningún filtro.
  ///
  /// `ChannelRef` usa la URL **canónica** (ADR-006, sin credenciales) como
  /// segunda prioridad de la cascada si no hay `epg_channel_id` — nunca la
  /// URL reproducible real, que llevaría la contraseña del panel.
  static Channel liveStreamToChannel({
    required String sourceId,
    required XtreamLiveStream stream,
    Map<String, String> categoryNames = const {},
  }) {
    final canonicalUrl = XtreamUrlResolver.liveCanonical(
      sourceId: sourceId,
      streamId: stream.streamId.toString(),
    );
    final categoryName = stream.categoryId == null
        ? null
        : (categoryNames[stream.categoryId] ?? stream.categoryId);

    return Channel(
      ref: ChannelRef.derive(
        sourceId: sourceId,
        tvgId: stream.epgChannelId,
        url: canonicalUrl.toString(),
        name: stream.name,
      ),
      sourceId: sourceId,
      categoryId: categoryName == null
          ? null
          : Category.derive(sourceId: sourceId, type: ContentType.live, name: categoryName).id,
      type: ContentType.live,
      name: stream.name,
      url: canonicalUrl,
      tvgId: stream.epgChannelId,
      logo: stream.streamIcon == null ? null : Uri.tryParse(stream.streamIcon!),
      metadata: {
        'x-xtream-stream-id': stream.streamId.toString(),
        if (stream.hasTvArchive) 'x-xtream-tv-archive': '1',
      },
    );
  }

  /// Película cruda (`get_vod_streams`) → `core.Channel(type: vod)`. Xtream
  /// no tiene equivalente de `tvg-id` para VOD, así que `ChannelRef`
  /// siempre cae a la forma canónica **sin extensión**
  /// (`XtreamUrlResolver.movieRefCanonical`) — nunca a la reproducible, y
  /// nunca a una que incluya `container_extension` (ADR-006: un panel que
  /// reetiqueta `mkv`→`mp4` no debe romper el favorito).
  static Channel vodStreamToChannel({
    required String sourceId,
    required XtreamVodStream stream,
    Map<String, String> categoryNames = const {},
  }) {
    final playbackUrl = XtreamUrlResolver.movieCanonical(
      sourceId: sourceId,
      streamId: stream.streamId.toString(),
      containerExtension: stream.containerExtension,
    );
    final refUrl = XtreamUrlResolver.movieRefCanonical(
      sourceId: sourceId,
      streamId: stream.streamId.toString(),
    );
    final categoryName = stream.categoryId == null
        ? null
        : (categoryNames[stream.categoryId] ?? stream.categoryId);

    return Channel(
      ref: ChannelRef.derive(sourceId: sourceId, url: refUrl.toString(), name: stream.name),
      sourceId: sourceId,
      categoryId: categoryName == null
          ? null
          : Category.derive(sourceId: sourceId, type: ContentType.vod, name: categoryName).id,
      type: ContentType.vod,
      name: stream.name,
      url: playbackUrl,
      logo: stream.streamIcon == null ? null : Uri.tryParse(stream.streamIcon!),
      metadata: {
        'x-xtream-stream-id': stream.streamId.toString(),
        if (stream.containerExtension != null) 'x-xtream-container': stream.containerExtension!,
        if (stream.rating != null) 'x-xtream-rating': stream.rating!.toString(),
      },
    );
  }

  /// Un episodio → `core.Channel(type: series)`, **bajo demanda** (al
  /// abrir la ficha de una serie ya consultada con `seriesInfo()`), no
  /// invocado durante `importChannels()` — un import completo no puede
  /// pedir `get_series_info` de cada serie del panel (N+1 de red, ver
  /// diseño de T1.4). `seasonNumber` es la clave del mapa
  /// `episodesBySeason` (la fuente de verdad real, ver
  /// `XtreamSeriesInfo`), no `episode.season` ni `XtreamSeason.seasonNumber`.
  static Channel episodeToChannel({
    required String sourceId,
    required int seriesId,
    required int seasonNumber,
    required XtreamEpisode episode,
    Map<String, String> categoryNames = const {},
    String? categoryId,
  }) {
    final playbackUrl = XtreamUrlResolver.seriesCanonical(
      sourceId: sourceId,
      episodeId: episode.id,
      containerExtension: episode.containerExtension,
    );
    final refUrl = XtreamUrlResolver.seriesRefCanonical(sourceId: sourceId, episodeId: episode.id);
    final categoryName = categoryId == null ? null : (categoryNames[categoryId] ?? categoryId);

    return Channel(
      ref: ChannelRef.derive(sourceId: sourceId, url: refUrl.toString(), name: episode.title),
      sourceId: sourceId,
      categoryId: categoryName == null
          ? null
          : Category.derive(sourceId: sourceId, type: ContentType.series, name: categoryName).id,
      type: ContentType.series,
      name: episode.title,
      url: playbackUrl,
      metadata: {
        'x-xtream-series-id': seriesId.toString(),
        'x-xtream-season': seasonNumber.toString(),
        'x-xtream-episode': episode.episodeNum.toString(),
        if (episode.containerExtension != null) 'x-xtream-container': episode.containerExtension!,
      },
    );
  }
}
