import 'package:iptv_core/iptv_core.dart';

/// `WatchStateRepository` en memoria para los tests de Home desktop (S5 ·
/// Ola 1) — mismo criterio que el resto de fakes del repo: sin drift,
/// `seed` deja al test sembrar directamente sin pasar por
/// `TrackWatchProgress.updateProgress` (que además exige un reloj).
final class FakeWatchStateRepository implements WatchStateRepository {
  final Map<ChannelRef, WatchState> _byChannel = {};

  void seed(WatchState state) => _byChannel[state.channel] = state;

  @override
  Future<List<WatchState>> getAll() async => _byChannel.values.toList();

  @override
  Future<WatchState?> find(ChannelRef channel) async => _byChannel[channel];

  @override
  Future<void> upsert(WatchState state) async {
    _byChannel[state.channel] = state;
  }
}
