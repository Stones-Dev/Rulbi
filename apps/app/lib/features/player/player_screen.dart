import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_playback/iptv_playback.dart';

import '../../shell/form_factor.dart';
import '../epg/epg_providers.dart';
import '../sources/source_providers.dart';
import 'mobile_player_gestures.dart';
import 'playback_request.dart';
import 'player_controller.dart';
import 'player_overlay.dart';
import 'player_providers.dart';
import 'tv_channel_drawer.dart';

/// Superficie de vídeo real polimórfica (Desktop y Android) — construida
/// en producción por [createPlayerPort]. `PlayerScreen.buildSurface` es el
/// punto de inyección que la sustituye en tests.
Widget _defaultBuildSurface(PlayerPort port, BoxFit fit) =>
    PlayerSurface(player: port, fit: fit);

/// Reproductor adaptativo (ui-spec §2.13, S6 desktop, S9 Android TV/móvil):
/// - TV: atajos D-pad (↑/↓ zapping < 2s, select/center play/pause, tecla lista/menú
///   abre panel lateral de canales Figma 45:22).
/// - Móvil: gestos táctiles con HUD (brillo, volumen, seek horizontal, doble tap ±10s, PiP).
/// - Desktop: atajos de teclado y rueda de ratón para volumen.
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

    final formFactor = FormFactorDetector.detect();
    if (formFactor == FormFactor.mobile) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }

    unawaited(_controller.initialize());
  }

  @override
  void dispose() {
    final formFactor = FormFactorDetector.detect();
    if (formFactor == FormFactor.mobile) {
      SystemChrome.setPreferredOrientations([]);
    }

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
    final isMobile = FormFactorDetector.detect() == FormFactor.mobile;

    Widget surface = widget._buildSurface(_port, _fit);
    if (isMobile) {
      surface = MobilePlayerGestures(
        controller: _controller,
        child: surface,
      );
    } else {
      surface = MouseRegion(
        onHover: (_) => _controller.show(),
        child: Listener(
          onPointerSignal: _handleWheel,
          child: GestureDetector(
            onTap: () => _controller.show(),
            behavior: HitTestBehavior.opaque,
            child: surface,
          ),
        ),
      );
    }

    final content = ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => Stack(
        fit: StackFit.expand,
        children: [
          surface,
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
          if (_controller.channelDrawerVisible)
            TvChannelDrawer(
              controller: _controller,
              onClose: () => _controller.closeChannelDrawer(),
            ),
        ],
      ),
    );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): () {
          unawaited(_controller.togglePlayPause());
          _controller.show();
        },
        const SingleActivator(LogicalKeyboardKey.select): () {
          unawaited(_controller.togglePlayPause());
          _controller.show();
        },
        const SingleActivator(LogicalKeyboardKey.enter): () {
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
          if (_controller.channelDrawerVisible) {
            _controller.closeChannelDrawer();
          } else {
            unawaited(_controller.seekBy(const Duration(seconds: -10)));
            _controller.show();
          }
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
        // Tecla lista / Menú en mando de TV abre/cierra panel lateral (Figma 45:22)
        const SingleActivator(LogicalKeyboardKey.keyL): () {
          _controller.toggleChannelDrawer();
        },
        const SingleActivator(LogicalKeyboardKey.contextMenu): () {
          _controller.toggleChannelDrawer();
        },
      },
      child: Focus(
        autofocus: true,
        child: PopScope(
          canPop: !_controller.channelDrawerVisible,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && _controller.channelDrawerVisible) {
              _controller.closeChannelDrawer();
            }
          },
          child: Scaffold(
            backgroundColor: Colors.black,
            body: content,
          ),
        ),
      ),
    );
  }
}

