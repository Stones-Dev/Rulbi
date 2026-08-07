import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_playback/iptv_playback.dart';

import '../epg/epg_providers.dart';
import '../sources/source_providers.dart';
import 'playback_request.dart';
import 'player_controller.dart';
import 'player_overlay.dart';
import 'player_providers.dart';

/// Superficie de vídeo real, tipada sobre `MediaKitPlayer` (el único
/// motor de escritorio hoy, ADR-009) — construida en producción por
/// [createPlayerPort]. `PlayerScreen.buildSurface` es el punto de
/// inyección que la sustituye en tests (ver docstring de la clase).
Widget _defaultBuildSurface(PlayerPort port, BoxFit fit) =>
    PlayerSurface(player: port as MediaKitPlayer, fit: fit);

/// Reproductor desktop (ui-spec §2.13, S6): superficie de vídeo +
/// [PlayerOverlay] autoocultable, atajos de teclado y persistencia de
/// `watch_state` (vía [PlayerController]). Se abre exclusivamente a través
/// de `openPlayer` (`open_player.dart`, D4 del plan de la ola) — ninguna
/// otra pantalla hace `Navigator.push` directo a este widget.
///
/// [createPort]/[buildSurface] son puntos de inyección — por defecto
/// [createPlayerPort] (`MediaKitPlayer` real) y [_defaultBuildSurface]
/// (el widget `Video` real de media_kit). `player_screen_test.dart` los
/// sustituye por un `FakePlayerPort` y un marcador de posición: ese motor
/// nativo no es testeable en CI (necesita libmpv enlazado, ver docstring
/// de `MediaKitPlayer`), pero los atajos/overlay que este widget cablea sí
/// lo son — sin este seam, esa cobertura tampoco sería posible.
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({
    super.key,
    required this.request,
    PlayerPort Function()? createPort,
    Widget Function(PlayerPort port, BoxFit fit)? buildSurface,
  }) : _createPort = createPort ?? createPlayerPort,
       _buildSurface = buildSurface ?? _defaultBuildSurface;

  final PlaybackRequest request;
  final PlayerPort Function() _createPort;
  final Widget Function(PlayerPort port, BoxFit fit) _buildSurface;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  late final PlayerPort _port;
  late final PlayerController _controller;
  late final EpgNowController _epgController;
  BoxFit _fit = BoxFit.contain;

  @override
  void initState() {
    super.initState();
    _port = widget._createPort();
    _controller = PlayerController(
      port: _port,
      resolver: ref.read(playbackUrlResolverProvider),
      trackWatchProgress: ref.read(trackWatchProgressProvider),
      request: widget.request,
    );
    _epgController = createEpgNowController(ref);
    unawaited(_controller.initialize());
  }

  @override
  void dispose() {
    _controller.dispose();
    unawaited(_port.dispose());
    _epgController.dispose();
    super.dispose();
  }

  void _handleWheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    // Rueda arriba (scrollDelta.dy negativo) = subir volumen (ui-spec
    // §2.13: "rueda = volumen").
    unawaited(_controller.adjustVolume(event.scrollDelta.dy < 0 ? 0.05 : -0.05));
    _controller.show();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): () {
          unawaited(_controller.togglePlayPause());
          _controller.show();
        },
        const SingleActivator(LogicalKeyboardKey.keyF): () {
          _controller.toggleFullscreen();
          _controller.show();
        },
        const SingleActivator(LogicalKeyboardKey.keyM): () {
          unawaited(_controller.toggleMuted());
          _controller.show();
        },
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
          unawaited(_controller.seekBy(const Duration(seconds: -10)));
          _controller.show();
        },
        const SingleActivator(LogicalKeyboardKey.arrowRight): () {
          unawaited(_controller.seekBy(const Duration(seconds: 10)));
          _controller.show();
        },
        // ↑/↓ zapean sobre la PlaybackQueue (D3 del plan): ↑ = anterior, ↓
        // = siguiente, mismo sentido que "canal arriba/abajo" de un mando
        // real.
        const SingleActivator(LogicalKeyboardKey.arrowUp): () {
          unawaited(_controller.previous());
          _controller.show();
        },
        const SingleActivator(LogicalKeyboardKey.arrowDown): () {
          unawaited(_controller.next());
          _controller.show();
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: MouseRegion(
            onHover: (_) => _controller.show(),
            child: Listener(
              onPointerSignal: _handleWheel,
              child: GestureDetector(
                onTap: () => _controller.show(),
                behavior: HitTestBehavior.opaque,
                child: ListenableBuilder(
                  listenable: _controller,
                  builder: (context, _) => Stack(
                    fit: StackFit.expand,
                    children: [
                      widget._buildSurface(_port, _fit),
                      StreamBuilder<PlaybackState>(
                        stream: _port.state,
                        initialData: _port.currentState,
                        builder: (context, stateSnapshot) => StreamBuilder<PlayerTracks>(
                          stream: _port.tracks,
                          initialData: PlayerTracks.empty,
                          builder: (context, tracksSnapshot) => PlayerOverlay(
                            controller: _controller,
                            playbackState: stateSnapshot.data ?? _port.currentState,
                            tracks: tracksSnapshot.data ?? PlayerTracks.empty,
                            boxFit: _fit,
                            onBoxFitChanged: (fit) => setState(() => _fit = fit),
                            epgController: _controller.currentChannel.type == ContentType.live
                                ? _epgController
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
