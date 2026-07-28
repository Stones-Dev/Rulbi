import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'iptv_colors.dart';

/// Tipografía Inter (decidida en el tooling del proyecto, 2026-07-20).
abstract final class IptvTypography {
  static TextTheme textTheme(Brightness brightness) {
    final base = brightness == Brightness.dark
        ? const TextTheme().apply(
            bodyColor: IptvColors.textPrimary,
            displayColor: IptvColors.textPrimary,
          )
        : const TextTheme();
    return GoogleFonts.interTextTheme(base);
  }
}
