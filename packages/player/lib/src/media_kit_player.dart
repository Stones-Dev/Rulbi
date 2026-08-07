import 'dart:async';

import 'package:iptv_core/iptv_core.dart' as core;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Implementación real de [core.PlayerPort] para Windows/Linux (S6, ADR-009:
/// media_kit 1.2.6 sobre libmpv, modo LGPL). Único punto del repo, junto con
/// [PlayerSurface]/[IptvPlayback], que importa `package:media_kit*` — P6:
/// `core` y `apps/app` solo conocen [core.PlayerPort].
///
/// **Límite de cobertura declarado (S6)**: este adapter no es testeable en
/// CI (necesita libmpv nativo enlazado, ausente en el runner). Su
/// verificación es manual (`flutter run -d windows`/`-d linux`, ver
/// handoff de S6) — el contrato que sí se testea contra memoria pura es
/// [core.PlayerPort] (`packages/core/test/player_port_test.dart`).
final class MediaKitPlayer implements core.PlayerPort {
  MediaKitPlayer({Player? player}) : _player = player ?? Player() {
    _wire();
  }

  final Player _player;

  final _stateController = StreamController<core.PlaybackState>.broadcast();
  final _tracksController = StreamController<core.PlayerTracks>.broadcast();
  final List<StreamSubscription<void>> _subscriptions = [];

  core.PlaybackState _state = core.PlaybackState.idle;

  /// Controlador de vídeo de `media_kit_video` — no forma parte de
  /// [core.PlayerPort] (sería un tipo de Flutter/media_kit filtrando a
  /// `core`); [PlayerSurface] lo consume tipando este adapter concreto,
  /// nunca la interfaz.
  VideoController get videoController => _videoController;
  late final VideoController _videoController = VideoController(_player);

  void _wire() {
    _subscriptions.addAll([
      _player.stream.position.listen((position) => _update(position: position)),
      _player.stream.duration.listen((duration) => _update(duration: duration)),
      _player.stream.buffer.listen((buffered) => _update(buffered: buffered)),
      _player.stream.playing.listen(
        (playing) => _update(
          status: playing ? core.PlaybackStatus.playing : core.PlaybackStatus.paused,
        ),
      ),
      _player.stream.buffering.listen((buffering) {
        if (buffering) _update(status: core.PlaybackStatus.buffering);
      }),
      _player.stream.completed.listen((completed) {
        if (completed) _update(status: core.PlaybackStatus.ended);
      }),
      // media_kit reporta el volumen en [0, 100]; PlayerPort en [0, 1]
      // (ver docstring de PlaybackState.volume).
      _player.stream.volume.listen((volume) => _update(volume: volume / 100)),
      _player.stream.error.listen(
        (message) => _update(status: core.PlaybackStatus.failed, errorMessage: message),
      ),
      _player.stream.tracks.listen((_) => _syncTracks()),
      _player.stream.track.listen((_) => _syncTracks()),
    ]);
  }

  @override
  Stream<core.PlaybackState> get state => _stateController.stream;

  @override
  Stream<core.PlayerTracks> get tracks => _tracksController.stream;

  @override
  core.PlaybackState get currentState => _state;

  @override
  Future<void> open(
    Uri url, {
    Duration startAt = Duration.zero,
    Map<String, String> headers = const {},
  }) async {
    _update(status: core.PlaybackStatus.opening, position: Duration.zero);
    await _player.open(
      Media(url.toString(), httpHeaders: headers.isEmpty ? null : headers),
      play: true,
    );
    if (startAt > Duration.zero) {
      await _player.seek(startAt);
    }
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> togglePlayPause() => _player.playOrPause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume.clamp(0, 1) * 100);

  /// libmpv/media_kit no expone un "mute" nativo separado del volumen —
  /// se implementa guardando el volumen previo y llevándolo a 0/
  /// restaurándolo, el mismo patrón que cualquier reproductor de
  /// escritorio real.
  @override
  Future<void> setMuted(bool muted) async {
    if (muted) {
      _volumeBeforeMute = _state.volume;
      await _player.setVolume(0);
    } else {
      await _player.setVolume(_volumeBeforeMute.clamp(0, 1) * 100);
    }
    _update(muted: muted);
  }

  double _volumeBeforeMute = 1.0;

  @override
  Future<void> setAudioTrack(String trackId) async {
    for (final track in _player.state.tracks.audio) {
      if (track.id == trackId) {
        await _player.setAudioTrack(track);
        return;
      }
    }
  }

  @override
  Future<void> setSubtitleTrack(String? trackId) async {
    if (trackId == null) {
      await _player.setSubtitleTrack(SubtitleTrack.no());
      return;
    }
    for (final track in _player.state.tracks.subtitle) {
      if (track.id == trackId) {
        await _player.setSubtitleTrack(track);
        return;
      }
    }
  }

  @override
  Future<void> stop() async {
    await _player.pause();
    _update(status: core.PlaybackStatus.idle, position: Duration.zero);
  }

  @override
  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _stateController.close();
    await _tracksController.close();
    await _player.dispose();
  }

  void _update({
    core.PlaybackStatus? status,
    Duration? position,
    Duration? duration,
    Duration? buffered,
    double? volume,
    bool? muted,
    String? errorMessage,
  }) {
    final nextStatus = status ?? _state.status;
    _state = core.PlaybackState(
      status: nextStatus,
      position: position ?? _state.position,
      duration: duration ?? _state.duration,
      buffered: buffered ?? _state.buffered,
      volume: volume ?? _state.volume,
      muted: muted ?? _state.muted,
      // El mensaje de error solo tiene sentido mientras status siga
      // failed — un status distinto lo limpia (ver docstring de
      // PlaybackState.errorMessage).
      errorMessage: nextStatus == core.PlaybackStatus.failed
          ? (errorMessage ?? _state.errorMessage)
          : null,
    );
    if (!_stateController.isClosed) _stateController.add(_state);
  }

  /// `available.audio/subtitle` de media_kit incluye pistas técnicas
  /// (`id: "auto"`, `id: "no"`) que no son contenido real seleccionable
  /// por el usuario — se filtran aquí para que el selector de la UI solo
  /// liste pistas de verdad, igual que haría cualquier reproductor.
  void _syncTracks() {
    final available = _player.state.tracks;
    final selected = _player.state.track;

    final tracks = core.PlayerTracks(
      audio: [
        for (final t in available.audio)
          if (t.id != 'auto' && t.id != 'no')
            core.PlayerTrack(id: t.id, title: t.title, language: t.language),
      ],
      subtitle: [
        for (final t in available.subtitle)
          if (t.id != 'no') core.PlayerTrack(id: t.id, title: t.title, language: t.language),
      ],
      selectedAudioId: selected.audio.id == 'no' ? null : selected.audio.id,
      selectedSubtitleId: selected.subtitle.id == 'no' ? null : selected.subtitle.id,
    );
    if (!_tracksController.isClosed) _tracksController.add(tracks);
  }
}
