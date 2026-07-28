import '../entities/favorite.dart';
import '../sync/channel_ref.dart';

abstract interface class FavoritesRepository {
  Future<List<Favorite>> getAll();
  Future<Favorite?> find(ChannelRef channel);
  Future<void> upsert(Favorite favorite);
  Stream<List<Favorite>> watchAll();
}
