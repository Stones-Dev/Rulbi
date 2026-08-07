import 'dart:async';

import 'package:iptv_core/iptv_core.dart';

/// `PlayerPort` en memoria para los tests de `apps/app` (S6, Bloque C) —
/// no puede reutilizarse el fake de `packages/core/test/player_port_test
/// .dart` (privado, `_FakePlayerPort`, interno de ese paquete). Mismo
/// comportamiento, más un par de ganchos propios (`openedUrls`,
/// `durationOnOpen`, `emitPosition`) que `PlayerController` necesita
/// ejercitar sin depender de un motor real.
final class FakePlayerPort implements PlayerPort {
  final _stateController = StreamController<PlaybackState>.broadcast();
  final _tracksController = StreamController<PlayerTracks>.broadcast();

  PlaybackState _state = PlaybackState.idle;
  PlayerTracks _tracks = PlayerTracks.empty;

  final List<Uri> openedUrls = [];
  final List<Duration> openedStartAts = [];
  bool disposed = false;

  /// Lo que `open` deja como `duration` en el estado — fijado por el test
  /// antes de construir el `PlayerController`, igual que un motor real
  /// reportaría la duración del contenido recién abierto.
  Duration durationOnOpen = Duration.zero;

  void _emit(PlaybackState next) {
    _state = next;
    if (!_stateController.isClosed) _stateController.add(next);
  }

  @override
  Stream<PlaybackState> get state => _stateController.stream;

  @override
  Stream<PlayerTracks> get tracks => _tracksController.stream;

  @override
  PlaybackState get currentState => _state;

  /// Lectura síncrona del último snapshot de pistas — equivalente a
  /// `currentState` pero para `tracks`, útil en tests que no quieren
  /// depender de la temporización del stream.
  PlayerTracks get currentTracks => _tracks;

  @override
  Future<void> open(
    Uri url, {
    Duration startAt = Duration.zero,
    Map<String, String> headers = const {},
  }) async {
    openedUrls.add(url);
    openedStartAts.add(startAt);
    _emit(
      PlaybackState(status: PlaybackStatus.playing, position: startAt, duration: durationOnOpen),
    );
  }

  @override
  Future<void> play() async => _emit(_copyWith(status: PlaybackStatus.playing));

  @override
  Future<void> pause() async => _emit(_copyWith(status: PlaybackStatus.paused));

  @override
  Future<void> togglePlayPause() async {
    if (_state.status == PlaybackStatus.playing) {
      await pause();
    } else {
      await play();
    }
  }

  @override
  Future<void> seek(Duration position) async => _emit(_copyWith(position: position));

  @override
  Future<void> setVolume(double volume) async => _emit(_copyWith(volume: volume));

  @override
  Future<void> setMuted(bool muted) async => _emit(_copyWith(muted: muted));

  @override
  Future<void> setAudioTrack(String trackId) async {
    _tracks = PlayerTracks(
      audio: _tracks.audio,
      subtitle: _tracks.subtitle,
      selectedAudioId: trackId,
      selectedSubtitleId: _tracks.selectedSubtitleId,
    );
    if (!_tracksController.isClosed) _tracksController.add(_tracks);
  }

  @override
  Future<void> setSubtitleTrack(String? trackId) async {
    _tracks = PlayerTracks(
      audio: _tracks.audio,
      subtitle: _tracks.subtitle,
      selectedAudioId: _tracks.selectedAudioId,
      selectedSubtitleId: trackId,
    );
    if (!_tracksController.isClosed) _tracksController.add(_tracks);
  }

  @override
  Future<void> stop() async => _emit(PlaybackState.idle);

  @override
  Future<void> dispose() async {
    disposed = true;
    await _stateController.close();
    await _tracksController.close();
  }

  /// Fija las pistas disponibles como si el motor las acabara de
  /// descubrir tras `open` — el test lo llama antes de `initialize()`.
  void seedTracks(PlayerTracks tracks) {
    _tracks = tracks;
    if (!_tracksController.isClosed) _tracksController.add(tracks);
  }

  /// Simula el avance de la posición de reproducción (ningún motor real
  /// corre en el fake) — el test lo llama entre elapses de `fakeAsync`
  /// para que cada guardado periódico capture una posición distinta.
  void emitPosition(Duration position) => _emit(_copyWith(position: position));

  PlaybackState _copyWith({
    PlaybackStatus? status,
    Duration? position,
    double? volume,
    bool? muted,
  }) => PlaybackState(
    status: status ?? _state.status,
    position: position ?? _state.position,
    duration: _state.duration,
    buffered: _state.buffered,
    volume: volume ?? _state.volume,
    muted: muted ?? _state.muted,
  );
}
