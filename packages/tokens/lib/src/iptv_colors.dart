import 'package:flutter/widgets.dart';

/// Una paleta de acento del lenguaje visual v2 (ui-spec.md §2.16 + §5,
/// colección de variables "Rulbi — Color Tokens" del archivo de Figma
/// fusionado, 4 modos). Los 4 campos son exactamente los que varían entre
/// modos en Figma (`color/background`, `color/surface`, `color/accent`,
/// `color/accent-on`) — el resto de la paleta (texto, bordes, error) es
/// compartido por los 4 temas y vive en [IptvColors] como constantes fijas.
final class IptvColorPalette {
  const IptvColorPalette({
    required this.background,
    required this.surface,
    required this.accent,
    required this.accentOn,
  });

  /// Fondo base de la app.
  final Color background;

  /// Superficie elevada (tarjetas, paneles, barras).
  final Color surface;

  /// Color de acento: selección, foco, CTAs, halo (ui-spec.md §5.3).
  final Color accent;

  /// Color de texto/icono legible sobre [accent] (`color/accent-on` en
  /// Figma) — p. ej. la etiqueta de un botón relleno del color de acento.
  final Color accentOn;
}

/// Lenguaje visual fijado en Figma (archivo "IPTV — UI Diseño").
/// No cambiar estos valores sin actualizar también el archivo de Figma.
abstract final class IptvColors {
  /// Fondo base de la app (paleta [onyx], el único tema cableado hoy).
  static const Color background = Color(0xFF0B0F14);

  /// Superficie elevada (tarjetas, paneles, barras) (paleta [onyx]).
  static const Color surface = Color(0xFF151B24);

  /// Color de acento: selección, foco, CTAs (paleta [onyx]).
  static const Color accent = Color(0xFF3D7AFF);

  /// Texto primario sobre [background]/[surface].
  static const Color textPrimary = Color(0xFFF5F7FA);

  /// Texto secundario/atenuado.
  static const Color textSecondary = Color(0xFFA0AAB8);

  /// Bordes y separadores sutiles sobre [surface].
  static const Color border = Color(0xFF232B38);

  /// Estados de error (fuentes caídas, fallos de conexión).
  static const Color error = Color(0xFFE5484D);

  /// Paleta "onyx" — la única de las 4 variantes de acento del lenguaje
  /// visual v2 cableada en esta fase (S6.5, Implementación Desktop
  /// rediseñado). Las otras 3 (lime/orchid/vanilla) están descritas en las
  /// variables de Figma pero no tienen todavía un selector de usuario en
  /// Ajustes — construir ese selector es alcance nuevo, no de esta tarea.
  static const IptvColorPalette onyx = IptvColorPalette(
    background: background,
    surface: surface,
    accent: accent,
    accentOn: Color(0xFF06152F),
  );
}
