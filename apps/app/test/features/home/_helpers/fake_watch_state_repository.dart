import 'package:iptv_core/iptv_core.dart';

/// `WatchStateRepository` en memoria para los tests de Home desktop (S5 ·
/// Ola 1) — mismo criterio que el resto de fakes del repo: sin drift,
/// `seed` deja al test sembrar directamente sin pasar por
/// `TrackWatchProgress.updateProgress` (que además exige un reloj).
final class FakeWatchStateRepository implements WatchStateRepository {
  final Map<ChannelRef, WatchState> _byChannel = {};

  /// Historial completo de `upsert` en orden de llegada (S6, Bloque C:
  /// el controlador del reproductor guarda progreso cada 10 s sobre el
  /// mismo canal, así que el mapa por clave no basta para contar cuántas
  /// veces se llamó — hace falta la secuencia, no solo el último valor).
  final List<WatchState> upsertHistory = [];
  int get upsertCalls => upsertHistory.length;

  void seed(WatchState state) => _byChannel[state.channel] = state;

  @override
  Future<List<WatchState>> getAll() async => _byChannel.values.toList();

  @override
  Future<WatchState?> find(ChannelRef channel) async => _byChannel[channel];

  @override
  Future<void> upsert(WatchState state) async {
    _byChannel[state.channel] = state;
    upsertHistory.add(state);
  }
}
