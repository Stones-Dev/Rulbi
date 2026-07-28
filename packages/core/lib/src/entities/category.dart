import '../text/normalize.dart';
import 'content_type.dart';

/// Categoría de canales dentro de una fuente (plan §4.2). No implementa
/// [Syncable]: se deriva de la fuente en cada refresco, no se fusiona.
final class Category {
  const Category({
    required this.id,
    required this.sourceId,
    required this.type,
    required this.name,
    this.order = 0,
  });

  /// Deriva un id determinista a partir de `sourceId` + nombre normalizado
  /// (mismo espíritu que [ChannelRef.derive]: dos dispositivos que importan
  /// la misma lista deben derivar el mismo id de categoría sin coordinarse
  /// entre sí, sin depender de que el origen — p. ej. un `group-title` de
  /// M3U — traiga su propio identificador estable).
  factory Category.derive({
    required String sourceId,
    required ContentType type,
    required String name,
    int order = 0,
  }) => Category(
    id: '$sourceId::${normalizeForMatching(name)}',
    sourceId: sourceId,
    type: type,
    name: name,
    order: order,
  );

  final String id;
  final String sourceId;
  final ContentType type;
  final String name;
  final int order;

  @override
  bool operator ==(Object other) =>
      other is Category &&
      other.id == id &&
      other.sourceId == sourceId &&
      other.type == type &&
      other.name == name &&
      other.order == order;

  @override
  int get hashCode => Object.hash(id, sourceId, type, name, order);

  @override
  String toString() => 'Category($name, $type)';
}
