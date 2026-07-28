import '../sync/channel_ref.dart';
import '../sync/syncable.dart';

/// Un canal marcado como favorito por el usuario (HU-05). Entidad
/// transferible: se indexa por [ChannelRef], nunca por el `id` de fila de
/// `channels` — ver [ChannelRef] para el porqué.
final class Favorite with Syncable {
  const Favorite({
    required this.channel,
    required this.updatedAt,
    this.order = 0,
    this.deletedAt,
  });

  final ChannelRef channel;
  final int order;

  @override
  final DateTime updatedAt;

  @override
  final DateTime? deletedAt;

  Favorite markDeleted(DateTime at) =>
      Favorite(channel: channel, order: order, updatedAt: at, deletedAt: at);

  Favorite withOrder(int newOrder, DateTime at) => Favorite(
    channel: channel,
    order: newOrder,
    updatedAt: at,
    deletedAt: deletedAt,
  );

  @override
  bool operator ==(Object other) =>
      other is Favorite &&
      other.channel == channel &&
      other.order == order &&
      other.updatedAt == updatedAt &&
      other.deletedAt == deletedAt;

  @override
  int get hashCode => Object.hash(channel, order, updatedAt, deletedAt);

  @override
  String toString() => 'Favorite($channel, order: $order)';
}
