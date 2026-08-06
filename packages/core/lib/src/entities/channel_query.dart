import 'content_type.dart';

/// Criterio de un listado paginado de canales (ui-spec §2.3, S5 · Ola 1):
/// una sección (TV en directo/Cine/Series), opcionalmente una categoría
/// dentro de ella, y el conjunto de fuentes que deben contribuir.
///
/// [sourceIds] lo calcula quien orquesta (la app), nunca `data`: la regla
/// "fuente desactivada (oculta)" de ui-spec §2.3 es de negocio/presentación,
/// no de persistencia. Un conjunto vacío no significa "todas las fuentes" —
/// significa "ninguna", y por tanto cero resultados; para "todas" hay que
/// pasar explícitamente los ids de las fuentes activas y no borradas.
final class ChannelQuery {
  const ChannelQuery({
    required this.type,
    required this.sourceIds,
    this.categoryId,
  });

  final ContentType type;

  /// `null` = todas las categorías de [type] (pseudo-categoría "Todas").
  final String? categoryId;

  final Set<String> sourceIds;

  ChannelQuery withCategory(String? categoryId) => ChannelQuery(
    type: type,
    sourceIds: sourceIds,
    categoryId: categoryId,
  );

  @override
  bool operator ==(Object other) =>
      other is ChannelQuery &&
      other.type == type &&
      other.categoryId == categoryId &&
      other.sourceIds.length == sourceIds.length &&
      other.sourceIds.containsAll(sourceIds);

  @override
  int get hashCode =>
      Object.hash(type, categoryId, Object.hashAllUnordered(sourceIds));

  @override
  String toString() =>
      'ChannelQuery(type: $type, categoryId: $categoryId, '
      'sourceIds: $sourceIds)';
}
