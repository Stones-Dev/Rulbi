import 'package:flutter/material.dart';
import 'package:iptv_tokens/iptv_tokens.dart';

/// Botón circular de favorito con el rebote de `43:20`/`44:2` (S6.5, pasos
/// 7-8): `AnimatedScale` 1.0 → 1.3 → 1.0, `Curves.elasticOut` — un
/// momento deliberado, no un toggle discreto. Compartido entre
/// `VodDetailScreen` y `SeriesDetailScreen`, antes cada una llevaba su
/// propio `OutlinedButton.icon` sin animación.
class FavoriteBounceButton extends StatefulWidget {
  const FavoriteBounceButton({
    super.key,
    required this.itemKey,
    required this.isFavorite,
    required this.tooltip,
    required this.onPressed,
  });

  final Key itemKey;
  final bool isFavorite;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  State<FavoriteBounceButton> createState() => _FavoriteBounceButtonState();
}

class _FavoriteBounceButtonState extends State<FavoriteBounceButton> {
  static const _bounceDuration = Duration(milliseconds: 200);

  double _scale = 1.0;

  void _handleTap() {
    widget.onPressed();
    setState(() => _scale = 1.3);
    Future.delayed(_bounceDuration, () {
      if (mounted) setState(() => _scale = 1.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _scale,
      duration: _bounceDuration,
      curve: Curves.elasticOut,
      child: Material(
        color: IptvColors.surface,
        shape: const CircleBorder(side: BorderSide(color: IptvColors.border)),
        child: IconButton(
          key: widget.itemKey,
          tooltip: widget.tooltip,
          onPressed: _handleTap,
          icon: Icon(
            widget.isFavorite ? Symbols.favorite_rounded : Symbols.favorite_border_rounded,
            color: widget.isFavorite ? IptvColors.accent : IptvColors.textPrimary,
            fill: widget.isFavorite ? 1 : 0,
          ),
          iconSize: IptvIconSizes.action,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 44, height: 44),
        ),
      ),
    );
  }
}
