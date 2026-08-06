import '../entities/channel.dart';
import '../entities/content_type.dart';

abstract interface class ChannelSearchPort {
  /// Busca por nombre, insensible a acentos/mayúsculas (RNF-01: resultado
  /// percibido < 100 ms sobre 100k canales). La implementación real
  /// (T1.5/`data`) vive sobre el índice FTS5.
  ///
  /// [type] y [sourceIds] acotan la búsqueda (S5 · Ola 1, ui-spec §2.11:
  /// "resultados agrupados por tipo") — `null` en cualquiera de los dos
  /// significa "sin filtrar por ese eje", a diferencia de `ChannelQuery`
  /// (entidad de listado paginado) donde un conjunto vacío de fuentes es
  /// explícito. `SearchChannels.grouped` es quien construye las tres
  /// llamadas por tipo; una única consulta sin agrupar sigue siendo
  /// válida con `type: null`.
  Future<List<Channel>> search(
    String query, {
    ContentType? type,
    Set<String>? sourceIds,
    int limit = 50,
  });
}
