import '../sync/channel_ref.dart';
import 'content_type.dart';

/// Un canal o ítem VOD/serie de una fuente (plan §4.2). No implementa
/// [Syncable]: se deriva de la fuente en cada refresco. Lo que sí es
/// estable es su [ref] ([ChannelRef]) — la clave que [Favorite] y
/// [WatchState] usan para sobrevivir a un refresco o a una transferencia
/// entre dispositivos.
final class Channel {
  const Channel({
    required this.ref,
    required this.sourceId,
    required this.type,
    required this.name,
    required this.url,
    this.categoryId,
    this.tvgId,
    this.logo,
    this.metadata = const {},
  });

  final ChannelRef ref;
  final String sourceId;
  final String? categoryId;
  final ContentType type;
  final String name;
  final Uri url;
  final String? tvgId;
  final Uri? logo;

  /// Atributos crudos del origen no modelados explícitamente (p. ej.
  /// `group-title`, `#EXTVLCOPT` de un M3U) — se conservan para no perder
  /// información, aunque `core` no les da significado propio.
  final Map<String, String> metadata;

  @override
  bool operator ==(Object other) =>
      other is Channel &&
      other.ref == ref &&
      other.sourceId == sourceId &&
      other.categoryId == categoryId &&
      other.type == type &&
      other.name == name &&
      other.url == url &&
      other.tvgId == tvgId &&
      other.logo == logo;

  @override
  int get hashCode => Object.hash(
        ref,
        sourceId,
        categoryId,
        type,
        name,
        url,
        tvgId,
        logo,
      );

  @override
  String toString() => 'Channel($name, $ref)';
}
