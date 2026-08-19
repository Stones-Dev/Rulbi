import 'package:flutter/widgets.dart';

/// Estilo de foco fijado en Figma: **anillo blanco + halo**. Se usa en los
/// tres shells, pero es especialmente crítico en `TvShell` (principio P9 —
/// la TV es ciudadana de primera; toda pantalla debe ser operable con D-pad
/// y el foco debe verse con claridad a distancia).
///
/// Desde S6.5 (Implementación Desktop rediseñado, ui-spec.md §5.3) el halo
/// deja de ser exclusivo del foco por teclado/mando: en Desktop también se
/// dispara en hover/pressed ("capa distintiva de Rulbi" en vez de sombra
/// gris de Material 3 genérico). El token en sí no cambia según el disparador
/// — quien decide cuándo mostrarlo es el widget que lo consume.
abstract final class IptvFocus {
  static const Color ringColor = Color(0xFFFFFFFF);
  static const double ringWidth = 2.5;

  /// Radio de desenfoque del halo — valor exacto del effect style de Figma
  /// "Elevation/Accent Halo" (`DROP_SHADOW`, `radius: 24`, `spread: 2`),
  /// confirmado con `get_variable_defs` sobre el archivo de diseño fusionado.
  /// Antes de S6.5 este valor era 12 (una aproximación anterior a tener el
  /// effect style medido) — corregido aquí, no es un cambio de patrón.
  static const double haloBlurRadius = 24;
  static const double haloSpreadRadius = 2;
  static const Color haloColor = Color(0x663D7AFF); // IptvColors.accent al 40%

  static List<BoxShadow> haloShadow() => const [
    BoxShadow(
      color: haloColor,
      blurRadius: haloBlurRadius,
      spreadRadius: haloSpreadRadius,
    ),
  ];

  static Border ring() => Border.all(color: ringColor, width: ringWidth);
}
