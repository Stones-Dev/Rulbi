import 'package:flutter/material.dart';

import 'iptv_colors.dart';
import 'iptv_typography.dart';

/// Tema único de la app (P2/P9: un solo lenguaje visual, tres shells).
/// Solo modo oscuro en v1 — el claro/OLED (ui-spec §2.15) llega con Ajustes.
abstract final class IptvTheme {
  static ThemeData dark() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: IptvColors.accent,
      brightness: Brightness.dark,
      surface: IptvColors.surface,
      error: IptvColors.error,
    );

    return ThemeData(
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: IptvColors.background,
      textTheme: IptvTypography.textTheme(Brightness.dark),
      useMaterial3: true,
    );
  }
}
