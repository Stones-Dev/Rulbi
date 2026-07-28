import '../entities/watch_state.dart';
import '../ports/clock.dart';
import '../ports/watch_state_repository.dart';
import '../sync/channel_ref.dart';

/// HU-10: continuar viendo. La persistencia periódica (cada 10 s y al
/// salir, ui-spec §2.13) es responsabilidad de quien controla el
/// reproductor (`PlayerPort`, fuera de `core`); este caso de uso solo
/// encapsula la escritura y la consulta, no el temporizador.
final class TrackWatchProgress {
  TrackWatchProgress(this._repository, this._clock);

  final WatchStateRepository _repository;
  final Clock _clock;

  Future<void> updateProgress(
    ChannelRef channel, {
    required Duration position,
    required Duration duration,
  }) {
    return _repository.upsert(WatchState(
      channel: channel,
      position: position,
      duration: duration,
      updatedAt: _clock.now(),
    ));
  }

  /// Candidatos a la fila "Continuar viendo" (ui-spec §2.2): con progreso
  /// real, sin terminar y sin borrar, más recientes primero.
  Future<List<WatchState>> continueWatching({int limit = 10}) async {
    final all = await _repository.getAll();
    final inProgress = all
        .where((w) => !w.isDeleted && !w.isFinished && w.position > Duration.zero)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return inProgress.take(limit).toList();
  }
}
