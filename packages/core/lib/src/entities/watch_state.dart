import '../sync/channel_ref.dart';
import '../sync/syncable.dart';

/// Progreso de reproducción de un canal/VOD/episodio (HU-10). Entidad
/// transferible, indexada por [ChannelRef]. Se persiste cada 10 s y al
/// salir del reproductor (ui-spec §2.13).
final class WatchState with Syncable {
  const WatchState({
    required this.channel,
    required this.position,
    required this.duration,
    required this.updatedAt,
    this.deletedAt,
  });

  final ChannelRef channel;
  final Duration position;

  /// `Duration.zero` para directo: no hay progreso que mostrar, solo que
  /// se vio.
  final Duration duration;

  @override
  final DateTime updatedAt;

  @override
  final DateTime? deletedAt;

  /// Progreso en `[0, 1]`; `0` si `duration` es cero (streams en directo,
  /// donde "progreso" no tiene sentido).
  double get fraction {
    if (duration.inMilliseconds == 0) return 0;
    final raw = position.inMilliseconds / duration.inMilliseconds;
    return raw.clamp(0, 1);
  }

  /// Umbral simple de "ya terminado" para no ofrecer "continuar viendo"
  /// en los últimos segundos de un VOD (créditos, etc.).
  bool get isFinished => fraction >= 0.95;

  WatchState markDeleted(DateTime at) => WatchState(
        channel: channel,
        position: position,
        duration: duration,
        updatedAt: at,
        deletedAt: at,
      );

  @override
  bool operator ==(Object other) =>
      other is WatchState &&
      other.channel == channel &&
      other.position == position &&
      other.duration == duration &&
      other.updatedAt == updatedAt &&
      other.deletedAt == deletedAt;

  @override
  int get hashCode =>
      Object.hash(channel, position, duration, updatedAt, deletedAt);

  @override
  String toString() => 'WatchState($channel, ${(fraction * 100).round()}%)';
}
