import 'package:flutter/widgets.dart';

/// Lenguaje visual fijado en Figma (archivo "IPTV — UI Diseño").
/// No cambiar estos valores sin actualizar también el archivo de Figma.
abstract final class IptvColors {
  /// Fondo base de la app.
  static const Color background = Color(0xFF0B0F14);

  /// Superficie elevada (tarjetas, paneles, barras).
  static const Color surface = Color(0xFF151B24);

  /// Color de acento: selección, foco, CTAs.
  static const Color accent = Color(0xFF3D7AFF);

  /// Texto primario sobre [background]/[surface].
  static const Color textPrimary = Color(0xFFF5F7FA);

  /// Texto secundario/atenuado.
  static const Color textSecondary = Color(0xFFA0AAB8);

  /// Bordes y separadores sutiles sobre [surface].
  static const Color border = Color(0xFF232B38);

  /// Estados de error (fuentes caídas, fallos de conexión).
  static const Color error = Color(0xFFE5484D);
}
