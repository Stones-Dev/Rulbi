import 'package:iptv_core/iptv_core.dart';

import 'xtream_category.dart';

/// Conversión de DTOs de protocolo Xtream a entidades de `core` — el único
/// sitio del cliente que conoce `sourceId` y las reglas de derivación
/// (`Category.derive`, `ChannelRef.derive`) que `core` ya define para
/// M3U. Funciones puras y estáticas: se testean sin red ni cliente,
/// reutilizadas por `XtreamClient.importChannels()` (T1.4, bloque de
/// import) y por cualquier código que solo necesite mapear un DTO ya
/// obtenido (p. ej. una categoría sola en la UI).
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
}
