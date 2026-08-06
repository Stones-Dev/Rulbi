import '../entities/channel.dart';
import '../ports/channel_repository.dart';
import 'track_watch_progress.dart';

/// Home desktop (ui-spec §2.2, S5 · Ola 1): un ítem de la fila "Continuar
/// viendo", ya hidratado con el canal completo — `WatchState` por sí solo
/// solo guarda el `ChannelRef`, no el nombre/logo que la fila necesita
/// pintar.
final class ContinueWatchingItem {
  const ContinueWatchingItem({
    required this.channel,
    required this.position,
    required this.duration,
  });

  final Channel channel;
  final Duration position;

  /// `Duration.zero` para directo — ver `WatchState.duration`.
  final Duration duration;

  /// Progreso en `[0, 1]`; `0` para directo (mismo criterio que
  /// `WatchState.fraction`, duplicado aquí porque este tipo no envuelve
  /// `WatchState` directamente).
  double get fraction {
    if (duration.inMilliseconds == 0) return 0;
    final raw = position.inMilliseconds / duration.inMilliseconds;
    return raw.clamp(0, 1);
  }

  Duration get remaining => duration - position;

  @override
  String toString() =>
      'ContinueWatchingItem(${channel.name}, ${(fraction * 100).round()}%)';
}

/// Compone `TrackWatchProgress.continueWatching()` (reutiliza su filtro de
/// "en progreso, no terminado, no borrado") con `ChannelRepository
/// .findByRefs` para hidratar cada referencia a su canal completo. Vive en
/// `core`, no en un provider de la UI (P6): la regla "descartar refs cuyo
/// canal ya no existe" (fuente eliminada desde que se guardó el progreso)
/// es de dominio, no de presentación.
final class GetContinueWatching {
  GetContinueWatching(this._trackWatchProgress, this._channels);

  final TrackWatchProgress _trackWatchProgress;
  final ChannelRepository _channels;

  Future<List<ContinueWatchingItem>> call({int limit = 10}) async {
    final states = await _trackWatchProgress.continueWatching(limit: limit);
    if (states.isEmpty) return const [];

    final channels = await _channels.findByRefs(
      states.map((s) => s.channel).toList(),
    );
    final byRef = {for (final channel in channels) channel.ref: channel};

    final items = <ContinueWatchingItem>[];
    for (final state in states) {
      final channel = byRef[state.channel];
      if (channel == null) continue; // fuente/canal ya no existe
      items.add(
        ContinueWatchingItem(
          channel: channel,
          position: state.position,
          duration: state.duration,
        ),
      );
    }
    return items;
  }
}
