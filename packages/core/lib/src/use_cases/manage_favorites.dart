import '../entities/favorite.dart';
import '../ports/clock.dart';
import '../ports/favorites_repository.dart';
import '../sync/channel_ref.dart';

/// HU-05: marcar/desmarcar favoritos y reordenarlos.
final class ManageFavorites {
  ManageFavorites(this._repository, this._clock);

  final FavoritesRepository _repository;
  final Clock _clock;

  /// Si el canal no es favorito (o lo fue y se borró), lo marca; si ya lo
  /// es, lo tumba (tombstone) en vez de eliminar la fila — el borrado
  /// debe propagarse al resto de dispositivos emparejados (ADR-002/003).
  Future<void> toggle(ChannelRef channel) async {
    final existing = await _repository.find(channel);
    final now = _clock.now();
    if (existing == null || existing.isDeleted) {
      await _repository.upsert(Favorite(channel: channel, updatedAt: now));
    } else {
      await _repository.upsert(existing.markDeleted(now));
    }
  }

  /// Reordena los favoritos vivos según el orden dado por el usuario.
  /// Los que no estén en [inOrder] (o estén borrados) no se tocan.
  Future<void> reorder(List<ChannelRef> inOrder) async {
    final now = _clock.now();
    for (var i = 0; i < inOrder.length; i++) {
      final existing = await _repository.find(inOrder[i]);
      if (existing != null && !existing.isDeleted) {
        await _repository.upsert(existing.withOrder(i, now));
      }
    }
  }
}
