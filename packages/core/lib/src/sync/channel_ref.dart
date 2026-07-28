import '../text/normalize.dart';

/// Identidad lógica estable de un canal, independiente del `id`
/// autoincremental de su fila local (plan §4.2, ADR-003).
///
/// Tras una transferencia entre dispositivos, la tabla `channels` del
/// receptor tiene sus propios `id` de fila: un [Favorite] o un
/// [WatchState] que apuntara al `id` local del emisor apuntaría, en el
/// receptor, a un canal cualquiera (o a ninguno). `ChannelRef` es la clave
/// que sobrevive al viaje porque se deriva del *contenido* del canal,
/// nunca de su posición en la tabla local.
final class ChannelRef {
  const ChannelRef({required this.sourceId, required this.key});

  /// Identificador estable de la fuente que originó el canal (el `id` de
  /// [Source], que ya es estable — no el `id` de fila de `channels`).
  final String sourceId;

  /// El `tvg-id` si existe; si no, la URL; si tampoco, el nombre
  /// normalizado. En ese orden de preferencia porque es el de mayor a
  /// menor estabilidad frente a un refresco de la fuente.
  final String key;

  /// Deriva el ref de los datos crudos de un canal, aplicando la cascada
  /// tvg-id → url → nombre y la misma normalización de acentos/mayúsculas
  /// que usa el índice FTS5: dos dispositivos que importan la misma lista
  /// deben derivar el mismo ref sin coordinarse entre sí.
  factory ChannelRef.derive({
    required String sourceId,
    String? tvgId,
    String? url,
    required String name,
  }) {
    final raw = (tvgId != null && tvgId.trim().isNotEmpty)
        ? tvgId
        : (url != null && url.trim().isNotEmpty)
        ? url
        : name;
    return ChannelRef(sourceId: sourceId, key: normalizeForMatching(raw));
  }

  /// Forma serializable estable, útil como clave de mapa o de fila en
  /// `data` sin tener que componer dos columnas en cada consulta.
  String get serialized => '$sourceId::$key';

  @override
  bool operator ==(Object other) =>
      other is ChannelRef && other.sourceId == sourceId && other.key == key;

  @override
  int get hashCode => Object.hash(sourceId, key);

  @override
  String toString() => 'ChannelRef($serialized)';
}
