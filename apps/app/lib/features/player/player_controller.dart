import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:iptv_core/iptv_core.dart';

import 'playback_request.dart';
import 'playback_url_resolver.dart';

/// Lógica de reproducción sin widgets (S6, Bloque C) — lo que
/// `player_screen_test.dart` no necesita para probar el temporizador de
/// `watch_state`, el autoocultado del overlay ni el zapping: nada de esto
/// depende de `BuildContext`.
///
/// Una instancia por apertura del reproductor — `openPlayer` la construye,
/// `PlayerScreen` la consume y la libera con `dispose()` al salir.
final class PlayerController extends ChangeNotifier {
  PlayerController({
    required this._port,
    required this._resolver,
    required this._trackWatchProgress,
    required PlaybackRequest request,
    this.progressInterval = const Duration(seconds: 10),
    this.overlayAutoHide = const Duration(seconds: 4),
  }) : _queue = request.queue ?? PlaybackQueue(items: [request.channel], index: 0),
       _initialStartAt = request.startAt;

  final PlayerPort _port;
  final PlaybackUrlResolver _resolver;
  final TrackWatchProgress _trackWatchProgress;
  final Duration progressInterval;
  final Duration overlayAutoHide;

  final Duration _initialStartAt;
  PlaybackQueue _queue;
  Timer? _progressTimer;
  Timer? _overlayHideTimer;
  bool _overlayVisible = true;

  /// `false` mientras `_resolver.resolve` no encuentra URL reproducible
  /// (ui-spec no define este estado explícitamente para desktop — se
  /// expone igual para que `PlayerScreen` pueda mostrar un mensaje en vez
  /// de una superficie de vídeo negra en silencio).
  bool _unplayable = false;

  PlayerPort get port => _port;
  Channel get currentChannel => _queue.current;
  PlaybackQueue get queue => _queue;
  bool get overlayVisible => _overlayVisible;
  bool get unplayable => _unplayable;
  bool get canGoPrevious => _queue.hasPrevious;
  bool get canGoNext => _queue.hasNext;

  bool _channelDrawerVisible = false;
  bool get channelDrawerVisible => _channelDrawerVisible;

  /// Presentación pura (D2 del plan: no es una orden al motor) — toggled
  /// por el atajo `F`. Sin `window_manager` en el árbol (fuera de alcance
  /// de esta ola, no estaba en el plan), esto no cambia el estado de la
  /// ventana del SO: `PlayerScreen` lo usa para ocultar el resto de chrome
  /// propio (barra superior con volver) y dejar solo vídeo + overlay
  /// autoocultable — declarado como desviación en el handoff de S6.
  bool _fullscreen = false;
  bool get isFullscreen => _fullscreen;

  void toggleChannelDrawer() {
    _channelDrawerVisible = !_channelDrawerVisible;
    if (_channelDrawerVisible) {
      _overlayHideTimer?.cancel();
    } else {
      _resetOverlayTimer();
    }
    notifyListeners();
  }

  void closeChannelDrawer() {
    if (!_channelDrawerVisible) return;
    _channelDrawerVisible = false;
    _resetOverlayTimer();
    notifyListeners();
  }

  Future<void> initialize() async {
    await _loadChannel(_queue.current, startAt: _initialStartAt);
    _progressTimer = Timer.periodic(progressInterval, (_) => unawaited(_saveProgress()));
    _resetOverlayTimer();
  }

  Future<void> _loadChannel(Channel channel, {Duration startAt = Duration.zero}) async {
    final url = await _resolver.resolve(channel);
    if (url == null) {
      _unplayable = true;
      notifyListeners();
      return;
    }
    _unplayable = false;
    await _port.open(url, startAt: startAt);
    notifyListeners();
  }

  Future<void> next() async {
    if (!_queue.hasNext) return;
    _queue = _queue.advance(1);
    await _loadChannel(_queue.current);
  }

  Future<void> previous() async {
    if (!_queue.hasPrevious) return;
    _queue = _queue.advance(-1);
    await _loadChannel(_queue.current);
  }

  Future<void> jumpTo(int index) async {
    if (index < 0 || index >= _queue.items.length) return;
    if (index == _queue.index) return;
    _queue = _queue.jumpTo(index);
    await _loadChannel(_queue.current);
  }

  Future<void> togglePlayPause() => _port.togglePlayPause();

  /// Ignorado en directo (ui-spec §2.13: seek solo tiene sentido en
  /// VOD) — evita que ←/→ intenten mover la posición de un stream en
  /// directo sin *time-shift*.
  Future<void> seekBy(Duration delta) {
    if (currentChannel.type == ContentType.live) return Future.value();
    final state = _port.currentState;
    var target = state.position + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (state.duration > Duration.zero && target > state.duration) target = state.duration;
    return _port.seek(target);
  }

  Future<void> setMuted(bool muted) => _port.setMuted(muted);
  Future<void> toggleMuted() => _port.setMuted(!_port.currentState.muted);

  /// `delta` positivo sube volumen — pensado para la rueda del ratón
  /// (ui-spec §2.13: "rueda = volumen"), recortado a `[0, 1]`.
  Future<void> adjustVolume(double delta) {
    final target = (_port.currentState.volume + delta).clamp(0.0, 1.0);
    return _port.setVolume(target);
  }

  void toggleFullscreen() {
    _fullscreen = !_fullscreen;
    notifyListeners();
  }

  /// Cualquier interacción (mover el ratón, pulsar una tecla) llama esto —
  /// muestra el overlay si estaba oculto y reinicia el temporizador de
  /// autoocultado (ui-spec §2.13: "autoocultable, 4 s").
  void show() {
    if (!_overlayVisible) {
      _overlayVisible = true;
      notifyListeners();
    }
    _resetOverlayTimer();
  }

  void _resetOverlayTimer() {
    _overlayHideTimer?.cancel();
    _overlayHideTimer = Timer(overlayAutoHide, () {
      _overlayVisible = false;
      notifyListeners();
    });
  }

  Future<void> _saveProgress() async {
    final state = _port.currentState;
    final isLive = currentChannel.type == ContentType.live;
    await _trackWatchProgress.updateProgress(
      currentChannel.ref,
      position: state.position,
      // `Duration.zero` en directo (mismo criterio que `WatchState
      // .duration`) — nunca lo que reporte el motor para un stream sin
      // fin definido.
      duration: isLive ? Duration.zero : state.duration,
    );
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _overlayHideTimer?.cancel();
    // Último guardado "al salir" (ui-spec §2.13) — fire-and-forget porque
    // `ChangeNotifier.dispose()` es síncrono; `_saveProgress` no toca
    // ningún widget, solo el repositorio, así que completar después de
    // este método retornar es seguro.
    unawaited(_saveProgress());
    super.dispose();
  }
}
