import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_tokens/iptv_tokens.dart';

import 'player_controller.dart';

/// Detector y HUD de gestos táctiles para reproductor móvil (ui-spec §2.13, S9).
///
/// Soporta:
/// - Deslizamiento vertical izquierdo: ajuste de brillo con HUD visual.
/// - Deslizamiento vertical derecho: ajuste de volumen con HUD visual.
/// - Deslizamiento horizontal: seek en VOD con indicador de tiempo relativo.
/// - Doble tap izquierda: salto atrás de -10 s con animación.
/// - Doble tap derecha: salto adelante de +10 s con animación.
/// - Tap simple: alternar visibilidad del overlay.
class MobilePlayerGestures extends StatefulWidget {
  const MobilePlayerGestures({
    super.key,
    required this.controller,
    required this.child,
    this.initialBrightness = 0.8,
  });

  final PlayerController controller;
  final Widget child;
  final double initialBrightness;

  @override
  State<MobilePlayerGestures> createState() => _MobilePlayerGesturesState();
}

class _MobilePlayerGesturesState extends State<MobilePlayerGestures> {
  late double _brightness;
  Timer? _hudHideTimer;

  // Estado del HUD
  bool _showVolumeHud = false;
  double _hudVolume = 1.0;

  bool _showBrightnessHud = false;
  double _hudBrightness = 0.8;

  bool _showSeekHud = false;
  Duration _seekDelta = Duration.zero;

  bool _showDoubleTapLeft = false;
  bool _showDoubleTapRight = false;
  Timer? _doubleTapTimer;

  // Drag tracking
  bool _isVerticalDrag = false;
  bool _isHorizontalDrag = false;
  bool _isLeftDrag = false;

  @override
  void initState() {
    super.initState();
    _brightness = widget.initialBrightness;
  }

  @override
  void dispose() {
    _hudHideTimer?.cancel();
    _doubleTapTimer?.cancel();
    super.dispose();
  }

  void _triggerDoubleTapFeedback({required bool isRight}) {
    _doubleTapTimer?.cancel();
    setState(() {
      if (isRight) {
        _showDoubleTapRight = true;
        _showDoubleTapLeft = false;
      } else {
        _showDoubleTapLeft = true;
        _showDoubleTapRight = false;
      }
    });

    _doubleTapTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) {
        setState(() {
          _showDoubleTapLeft = false;
          _showDoubleTapRight = false;
        });
      }
    });
  }

  void _showHudTemporarily() {
    _hudHideTimer?.cancel();
    _hudHideTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) {
        setState(() {
          _showVolumeHud = false;
          _showBrightnessHud = false;
          _showSeekHud = false;
        });
      }
    });
  }

  void _onVerticalDragStart(DragStartDetails details, BoxConstraints constraints) {
    _isLeftDrag = details.localPosition.dx < (constraints.maxWidth * 0.5);
    _isVerticalDrag = true;
    _isHorizontalDrag = false;
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (!_isVerticalDrag) return;

    // delta negativo = arrastrar hacia arriba (aumentar valor)
    final delta = -details.primaryDelta! / 200.0;

    if (_isLeftDrag) {
      // Brillo en el lado izquierdo
      setState(() {
        _brightness = (_brightness + delta).clamp(0.05, 1.0);
        _hudBrightness = _brightness;
        _showBrightnessHud = true;
        _showVolumeHud = false;
        _showSeekHud = false;
      });
      _showHudTemporarily();
    } else {
      // Volumen en el lado derecho
      unawaited(widget.controller.adjustVolume(delta));
      setState(() {
        _hudVolume = widget.controller.port.currentState.volume;
        _showVolumeHud = true;
        _showBrightnessHud = false;
        _showSeekHud = false;
      });
      _showHudTemporarily();
    }
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    _isVerticalDrag = false;
    _showHudTemporarily();
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    if (widget.controller.currentChannel.type == ContentType.live) return;
    _isHorizontalDrag = true;
    _isVerticalDrag = false;
    _seekDelta = Duration.zero;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (!_isHorizontalDrag) return;
    if (widget.controller.currentChannel.type == ContentType.live) return;

    // 1 pixel = 0.5 segundos de seek
    final deltaSeconds = (details.primaryDelta! * 0.5).round();
    _seekDelta += Duration(seconds: deltaSeconds);

    setState(() {
      _showSeekHud = true;
      _showVolumeHud = false;
      _showBrightnessHud = false;
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (!_isHorizontalDrag) return;
    _isHorizontalDrag = false;

    if (_seekDelta != Duration.zero) {
      unawaited(widget.controller.seekBy(_seekDelta));
    }
    _showHudTemporarily();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            widget.controller.show();
          },
          onDoubleTapDown: (details) {
            final x = details.localPosition.dx;
            final isRight = x >= (constraints.maxWidth * 0.5);

            if (isRight) {
              unawaited(widget.controller.seekBy(const Duration(seconds: 10)));
              _triggerDoubleTapFeedback(isRight: true);
            } else {
              unawaited(widget.controller.seekBy(const Duration(seconds: -10)));
              _triggerDoubleTapFeedback(isRight: false);
            }
            widget.controller.show();
          },
          onVerticalDragStart: (d) => _onVerticalDragStart(d, constraints),
          onVerticalDragUpdate: _onVerticalDragUpdate,
          onVerticalDragEnd: _onVerticalDragEnd,
          onHorizontalDragStart: _onHorizontalDragStart,
          onHorizontalDragUpdate: _onHorizontalDragUpdate,
          onHorizontalDragEnd: _onHorizontalDragEnd,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Contenido base del reproductor
              widget.child,

              // Filtro de brillo simulado sobre la superficie
              if (_brightness < 1.0)
                IgnorePointer(
                  child: Container(
                    color: Colors.black.withValues(
                      alpha: (1.0 - _brightness) * 0.85,
                    ),
                  ),
                ),

              // HUD Brillo (lado izquierdo)
              if (_showBrightnessHud)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 36),
                    child: _OsdIndicator(
                      icon: Icons.brightness_medium_rounded,
                      label: '${(_hudBrightness * 100).round()}%',
                      progress: _hudBrightness,
                    ),
                  ),
                ),

              // HUD Volumen (lado derecho)
              if (_showVolumeHud)
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 36),
                    child: _OsdIndicator(
                      icon: _hudVolume > 0
                          ? Icons.volume_up_rounded
                          : Icons.volume_off_rounded,
                      label: '${(_hudVolume * 100).round()}%',
                      progress: _hudVolume,
                    ),
                  ),
                ),

              // HUD Seek horizontal
              if (_showSeekHud)
                Center(
                  child: _SeekIndicator(delta: _seekDelta),
                ),

              // Animación Doble Tap Izquierda (-10s)
              if (_showDoubleTapLeft)
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.only(left: 48),
                    child: _DoubleTapRipple(
                      icon: Icons.replay_10_rounded,
                      label: '-10s',
                    ),
                  ),
                ),

              // Animación Doble Tap Derecha (+10s)
              if (_showDoubleTapRight)
                const Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: EdgeInsets.only(right: 48),
                    child: _DoubleTapRipple(
                      icon: Icons.forward_10_rounded,
                      label: '+10s',
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _OsdIndicator extends StatelessWidget {
  const _OsdIndicator({
    required this.icon,
    required this.label,
    required this.progress,
  });

  final IconData icon;
  final String label;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 140,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: IptvColors.surface.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: IptvColors.border,
          width: 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: IptvColors.accent, size: 22),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: RotatedBox(
                quarterTurns: 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: IptvColors.border,
                    valueColor: const AlwaysStoppedAnimation(IptvColors.accent),
                  ),
                ),
              ),
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: IptvColors.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _SeekIndicator extends StatelessWidget {
  const _SeekIndicator({required this.delta});

  final Duration delta;

  @override
  Widget build(BuildContext context) {
    final isForward = delta >= Duration.zero;
    final absSec = delta.inSeconds.abs();
    final minutes = absSec ~/ 60;
    final seconds = absSec % 60;
    final sign = isForward ? '+' : '-';
    final text = '$sign${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: IptvColors.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: IptvColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isForward ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded,
            color: IptvColors.accent,
            size: 28,
          ),
          const SizedBox(width: 12),
          Text(
            text,
            style: const TextStyle(
              color: IptvColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _DoubleTapRipple extends StatelessWidget {
  const _DoubleTapRipple({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: IptvColors.accent.withValues(alpha: 0.25),
        shape: BoxShape.circle,
        border: Border.all(
          color: IptvColors.accent.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white, size: 28),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
