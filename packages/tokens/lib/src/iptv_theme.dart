import 'package:flutter/material.dart';

import 'iptv_colors.dart';
import 'iptv_density.dart';
import 'iptv_typography.dart';

/// Tema único de la app (P2/P9: un solo lenguaje visual, tres shells).
/// Solo modo oscuro en v1 — el claro/OLED (ui-spec §2.15) llega con Ajustes.
abstract final class IptvTheme {
  /// [palette] y [density] son opcionales y con valor por defecto
  /// [IptvColorPalette.onyx]/[IptvDensity.desktop] a propósito: llamar a
  /// `IptvTheme.dark()` sin argumentos (como hace hoy
  /// `apps/app/lib/main.dart`) produce exactamente el mismo `ThemeData` que
  /// antes de S6.5 — la estructura admite otras paletas/densidades, pero
  /// solo esta combinación está cableada en producción.
  static ThemeData dark({
    IptvColorPalette palette = IptvColors.onyx,
    IptvDensity density = IptvDensity.desktop,
  }) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: palette.accent,
      brightness: Brightness.dark,
      primary: palette.accent,
      onPrimary: palette.accentOn,
      surface: palette.surface,
      error: IptvColors.error,
    );

    return ThemeData(
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: palette.background,
      textTheme: IptvTypography.textTheme(Brightness.dark, density: density),
      useMaterial3: true,
    );
  }
}
