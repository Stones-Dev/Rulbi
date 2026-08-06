import '../entities/channel.dart';
import '../entities/content_type.dart';
import '../ports/channel_search_port.dart';

/// HU-04: búsqueda instantánea. Envuelve el puerto para dejar en un solo
/// sitio la regla de negocio "una consulta vacía no busca nada" — sin
/// esto, cada shell tendría que recordar comprobarlo antes de llamar al
/// puerto.
final class SearchChannels {
  SearchChannels(this._port);

  final ChannelSearchPort _port;

  Future<List<Channel>> call(String query, {int limit = 50}) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return Future.value(const []);
    return _port.search(trimmed, limit: limit);
  }

  /// Búsqueda global agrupada por tipo (ui-spec §2.11: "resultados
  /// agrupados por tipo (Canales / Películas / Series)"). Tres consultas
  /// acotadas por tipo en vez de una con `LIMIT` único: con un límite
  /// compartido, un tipo con muchos aciertos (p. ej. "la 1" entre miles de
  /// canales en directo) dejaría sin resultados a Películas/Series aunque
  /// también los tuvieran.
  ///
  /// [sourceIds], si no es null, restringe la búsqueda a esas fuentes —
  /// mismo criterio de "fuente desactivada (oculta)" que el listado
  /// (ui-spec §2.3): quien llama pasa las fuentes activas, no todas.
  Future<GroupedSearchResults> grouped(
    String query, {
    int limitPerType = 20,
    Set<String>? sourceIds,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const GroupedSearchResults.empty();

    final results = await Future.wait([
      _port.search(
        trimmed,
        type: ContentType.live,
        sourceIds: sourceIds,
        limit: limitPerType,
      ),
      _port.search(
        trimmed,
        type: ContentType.vod,
        sourceIds: sourceIds,
        limit: limitPerType,
      ),
      _port.search(
        trimmed,
        type: ContentType.series,
        sourceIds: sourceIds,
        limit: limitPerType,
      ),
    ]);

    return GroupedSearchResults(
      live: results[0],
      vod: results[1],
      series: results[2],
    );
  }
}

/// Resultado de [SearchChannels.grouped]: un grupo por [ContentType],
/// listo para las tres cabeceras de ui-spec §2.11 (Canales / Películas /
/// Series).
final class GroupedSearchResults {
  const GroupedSearchResults({
    required this.live,
    required this.vod,
    required this.series,
  });

  const GroupedSearchResults.empty() : this(live: const [], vod: const [], series: const []);

  final List<Channel> live;
  final List<Channel> vod;
  final List<Channel> series;

  bool get isEmpty => live.isEmpty && vod.isEmpty && series.isEmpty;

  @override
  String toString() =>
      'GroupedSearchResults(live: ${live.length}, vod: ${vod.length}, '
      'series: ${series.length})';
}
