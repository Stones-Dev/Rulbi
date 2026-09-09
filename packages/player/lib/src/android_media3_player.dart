import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:iptv_core/iptv_core.dart' as core;
import 'package:video_player/video_player.dart';

/// Implementación real de [core.PlayerPort] para Android / Android TV / Fire TV
/// (S9, plan.md §4.3) sobre AndroidX Media3 (ExoPlayer) vía `video_player`
/// 2.14+ (`video_player_android` 2.12+).
///
/// Soporta:
/// - Streams HLS (.m3u8) y MPEG-TS (.ts) de paneles IPTV.
/// - Archivos VOD MP4 y MKV.
/// - Envío de cabeceras HTTP personalizadas (User-Agent, Referer, auth).
/// - Posicionamiento nativo `startAt` (resume position) y seek.
/// - Cambio reactivo de pistas de audio mediante [VideoAudioTrack].
/// - Renderizado directo en textura por hardware (sin hybrid composition).
class AndroidMedia3Player extends ChangeNotifier implements core.PlayerPort {
  AndroidMedia3Player({
    VideoPlayerController Function(Uri url, Map<String, String> headers)?
        controllerFactory,
  }) : _controllerFactory = controllerFactory ?? _defaultControllerFactory;

  final VideoPlayerController Function(Uri url, Map<String, String> headers)
      _controllerFactory;

  static VideoPlayerController _defaultControllerFactory(
    Uri url,
    Map<String, String> headers,
  ) {
    return VideoPlayerController.networkUrl(
      url,
      httpHeaders: headers,
    );
  }

  VideoPlayerController? _controller;
  VideoPlayerController? get controller => _controller;

  final _stateController = StreamController<core.PlaybackState>.broadcast();
  final _tracksController = StreamController<core.PlayerTracks>.broadcast();

  core.PlaybackState _state = core.PlaybackState.idle;
  core.PlayerTracks _tracks = core.PlayerTracks.empty;

  double _volume = 1.0;
  bool _muted = false;
  bool _disposed = false;

  @override
  Stream<core.PlaybackState> get state => _stateController.stream;

  @override
  Stream<core.PlayerTracks> get tracks => _tracksController.stream;

  @override
  core.PlaybackState get currentState => _state;

  core.PlayerTracks get currentTracks => _tracks;

  void _updateState({
    core.PlaybackStatus? status,
    Duration? position,
    Duration? duration,
    Duration? buffered,
    double? volume,
    bool? muted,
    String? errorMessage,
  }) {
    if (_disposed) return;
    _state = core.PlaybackState(
      status: status ?? _state.status,
      position: position ?? _state.position,
      duration: duration ?? _state.duration,
      buffered: buffered ?? _state.buffered,
      volume: volume ?? _state.volume,
      muted: muted ?? _state.muted,
      errorMessage: errorMessage ?? _state.errorMessage,
    );
    if (!_stateController.isClosed) {
      _stateController.add(_state);
    }
  }

  @override
  Future<void> open(
    Uri url, {
    Duration startAt = Duration.zero,
    Map<String, String> headers = const {},
  }) async {
    _updateState(
      status: core.PlaybackStatus.opening,
      position: Duration.zero,
      duration: Duration.zero,
      buffered: Duration.zero,
    );

    await _disposeCurrentController();

    try {
      final ctrl = _controllerFactory(url, headers);
      _controller = ctrl;
      notifyListeners();

      ctrl.addListener(_handleControllerUpdate);
      await ctrl.initialize();

      if (startAt > Duration.zero) {
        await ctrl.seekTo(startAt);
      }

      await ctrl.setVolume(_muted ? 0.0 : _volume);
      await ctrl.play();

      await _syncTracks();
    } catch (e) {
      _updateState(
        status: core.PlaybackStatus.failed,
        errorMessage: e.toString(),
      );
    }
  }

  void _handleControllerUpdate() {
    final ctrl = _controller;
    if (ctrl == null || _disposed) return;

    final value = ctrl.value;
    if (value.hasError) {
      _updateState(
        status: core.PlaybackStatus.failed,
        errorMessage: value.errorDescription ?? 'Error en reproducción Media3',
      );
      return;
    }

    if (!value.isInitialized) {
      _updateState(status: core.PlaybackStatus.opening);
      return;
    }

    core.PlaybackStatus status;
    if (value.isBuffering) {
      status = core.PlaybackStatus.buffering;
    } else if (value.isCompleted) {
      status = core.PlaybackStatus.ended;
    } else if (value.isPlaying) {
      status = core.PlaybackStatus.playing;
    } else {
      status = core.PlaybackStatus.paused;
    }

    Duration bufferedMax = Duration.zero;
    if (value.buffered.isNotEmpty) {
      for (final range in value.buffered) {
        if (range.end > bufferedMax) {
          bufferedMax = range.end;
        }
      }
    }

    _updateState(
      status: status,
      position: value.position,
      duration: value.duration,
      buffered: bufferedMax,
      volume: _volume,
      muted: _muted,
    );
  }

  Future<void> _syncTracks() async {
    final ctrl = _controller;
    if (ctrl == null || _disposed || !ctrl.value.isInitialized) return;

    List<core.PlayerTrack> audioTracks = [];
    String? selectedAudioId;

    try {
      if (ctrl.isAudioTrackSupportAvailable()) {
        final platformAudio = await ctrl.getAudioTracks();
        audioTracks = platformAudio.map((track) {
          final label = track.label ?? track.language ?? track.id;
          if (track.isSelected) {
            selectedAudioId = track.id;
          }
          return core.PlayerTrack(
            id: track.id,
            title: label,
            language: track.language,
          );
        }).toList();
      }
    } catch (_) {
      // Degrada silenciosamente si el medio no provee metadatos de pistas
    }

    _tracks = core.PlayerTracks(
      audio: audioTracks,
      subtitle: const [],
      selectedAudioId: selectedAudioId,
      selectedSubtitleId: null,
    );

    if (!_tracksController.isClosed) {
      _tracksController.add(_tracks);
    }
  }

  @override
  Future<void> play() async {
    final ctrl = _controller;
    if (ctrl == null) return;
    await ctrl.play();
  }

  @override
  Future<void> pause() async {
    final ctrl = _controller;
    if (ctrl == null) return;
    await ctrl.pause();
  }

  @override
  Future<void> togglePlayPause() async {
    final ctrl = _controller;
    if (ctrl == null) return;
    if (ctrl.value.isPlaying) {
      await ctrl.pause();
    } else {
      await ctrl.play();
    }
  }

  @override
  Future<void> seek(Duration position) async {
    final ctrl = _controller;
    if (ctrl == null) return;
    await ctrl.seekTo(position);
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    final ctrl = _controller;
    if (ctrl == null) return;
    await ctrl.setVolume(_muted ? 0.0 : _volume);
    _updateState(volume: _volume);
  }

  @override
  Future<void> setMuted(bool muted) async {
    _muted = muted;
    final ctrl = _controller;
    if (ctrl == null) return;
    await ctrl.setVolume(_muted ? 0.0 : _volume);
    _updateState(muted: _muted);
  }

  @override
  Future<void> setAudioTrack(String trackId) async {
    final ctrl = _controller;
    if (ctrl == null) return;
    try {
      await ctrl.selectAudioTrack(trackId);
      await _syncTracks();
    } catch (_) {}
  }

  @override
  Future<void> setSubtitleTrack(String? trackId) async {
    // Media3 en video_player maneja subtítulos incrustados o closed captions
  }

  @override
  Future<void> stop() async {
    final ctrl = _controller;
    if (ctrl == null) return;
    await ctrl.pause();
    await ctrl.seekTo(Duration.zero);
    _updateState(status: core.PlaybackStatus.idle);
  }

  Future<void> _disposeCurrentController() async {
    final old = _controller;
    _controller = null;
    if (old != null) {
      old.removeListener(_handleControllerUpdate);
      await old.dispose();
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _disposeCurrentController();
    await _stateController.close();
    await _tracksController.close();
    super.dispose();
  }
}
