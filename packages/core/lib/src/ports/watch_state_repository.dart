import '../entities/watch_state.dart';
import '../sync/channel_ref.dart';

abstract interface class WatchStateRepository {
  Future<List<WatchState>> getAll();
  Future<WatchState?> find(ChannelRef channel);
  Future<void> upsert(WatchState state);
}
