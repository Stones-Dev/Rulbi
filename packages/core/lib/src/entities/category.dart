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
