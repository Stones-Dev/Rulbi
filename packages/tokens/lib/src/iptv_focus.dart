import 'package:flutter/widgets.dart';

/// Estilo de foco fijado en Figma: **anillo blanco + halo**. Se usa en los
/// tres shells, pero es especialmente crítico en `TvShell` (principio P9 —
/// la TV es ciudadana de primera; toda pantalla debe ser operable con D-pad
/// y el foco debe verse con claridad a distancia).
abstract final class IptvFocus {
  static const Color ringColor = Color(0xFFFFFFFF);
  static const double ringWidth = 2.5;
  static const double haloBlurRadius = 12;
  static const Color haloColor = Color(0x663D7AFF); // IptvColors.accent al 40%

  static List<BoxShadow> haloShadow() => const [
    BoxShadow(color: haloColor, blurRadius: haloBlurRadius, spreadRadius: 2),
  ];

  static Border ring() => Border.all(color: ringColor, width: ringWidth);
}
