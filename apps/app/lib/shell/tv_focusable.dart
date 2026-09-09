import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iptv_tokens/iptv_tokens.dart';

/// Componente reutilizable de foco D-pad para TV (S8 · TV base, RNF-08).
///
/// Encapsula:
/// - Anillo blanco + halo de acento (`IptvFocus.ring()` y `IptvFocus.haloShadow()`)
/// - Escala sutil con respuesta inmediata (120ms, ui-spec §5.4/motion)
/// - Accionamiento por D-pad Center / Enter (`LogicalKeyboardKey.select`, `enter`)
/// - Auto-scroll centrado dentro de vistas con scroll (Scrollable.ensureVisible)
class TvFocusable extends StatefulWidget {
  const TvFocusable({
    super.key,
    required this.child,
    this.onTap,
    this.focusNode,
    this.autofocus = false,
    this.borderRadius = IptvSpacing.radius,
    this.scale = 1.04,
    this.showRing = true,
    this.showHalo = true,
    this.padding,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final FocusNode? focusNode;
  final bool autofocus;
  final double borderRadius;
  final double scale;
  final bool showRing;
  final bool showHalo;
  final EdgeInsetsGeometry? padding;
  final String? semanticLabel;

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  late FocusNode _focusNode;
  bool _internalFocusNode = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode != null) {
      _focusNode = widget.focusNode!;
    } else {
      _focusNode = FocusNode();
      _internalFocusNode = true;
    }
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(TvFocusable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusNode != oldWidget.focusNode) {
      if (_internalFocusNode) {
        _focusNode.removeListener(_handleFocusChange);
        _focusNode.dispose();
        _internalFocusNode = false;
      }
      if (widget.focusNode != null) {
        _focusNode = widget.focusNode!;
      } else {
        _focusNode = FocusNode();
        _internalFocusNode = true;
      }
      _focusNode.addListener(_handleFocusChange);
    }
  }

  void _handleFocusChange() {
    final hasFocus = _focusNode.hasFocus;
    if (_focused != hasFocus) {
      setState(() => _focused = hasFocus);
      if (hasFocus && mounted) {
        // Auto-scroll para asegurar visibilidad en TV a 3 metros
        Scrollable.ensureVisible(
          context,
          alignment: 0.5,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    if (_internalFocusNode) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.select ||
          event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter ||
          event.logicalKey == LogicalKeyboardKey.space) {
        if (widget.onTap != null) {
          widget.onTap!();
          return KeyEventResult.handled;
        }
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(widget.borderRadius);

    return Semantics(
      label: widget.semanticLabel,
      button: widget.onTap != null,
      child: Focus(
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        onKeyEvent: _handleKeyEvent,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _focused ? widget.scale : 1.0,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOutCubic,
              padding: widget.padding,
              decoration: BoxDecoration(
                borderRadius: radius,
                border: _focused && widget.showRing ? IptvFocus.ring() : null,
                boxShadow:
                    _focused && widget.showHalo ? IptvFocus.haloShadow() : null,
              ),
              child: ClipRRect(
                borderRadius: radius,
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
