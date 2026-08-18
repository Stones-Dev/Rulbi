import 'package:flutter/material.dart';

import 'iptv_colors.dart';
import 'iptv_density.dart';

/// Escala tipográfica del lenguaje visual v2 (ui-spec.md §5.1, S6.5).
///
/// Familia Inter, empaquetada como asset del propio paquete
/// (`packages/tokens/fonts/`, 3 instancias estáticas Regular/SemiBold/Bold
/// extraídas de la fuente variable) — no vía `google_fonts`, para no
/// depender de red en el primer arranque de un reproductor IPTV que puede
/// no tener conectividad todavía.
///
/// 5 roles (Display/Headline/Title/Body/Label), cada uno con un tamaño para
/// Desktop y uno para TV (un escalón más grande). Los valores están
/// verificados 1:1 contra los text styles del archivo de Figma fusionado
/// (`get_variable_defs`, S6.5).
abstract final class IptvTypography {
  static const String fontFamily = 'Inter';

  // ---------------------------------------------------------------------
  // Display — títulos de sección en Home ("Continuar viendo").
  // ---------------------------------------------------------------------
  static const TextStyle displayDesktop = TextStyle(
    fontFamily: fontFamily,
    fontSize: 28,
    height: 36 / 28,
    fontWeight: FontWeight.w700,
  );
  static const TextStyle displayTv = TextStyle(
    fontFamily: fontFamily,
    fontSize: 36,
    height: 44 / 36,
    fontWeight: FontWeight.w700,
  );

  // ---------------------------------------------------------------------
  // Headline — títulos de ficha VOD/Serie.
  // ---------------------------------------------------------------------
  static const TextStyle headlineDesktop = TextStyle(
    fontFamily: fontFamily,
    fontSize: 24,
    height: 32 / 24,
    fontWeight: FontWeight.w700,
  );
  static const TextStyle headlineTv = TextStyle(
    fontFamily: fontFamily,
    fontSize: 32,
    height: 40 / 32,
    fontWeight: FontWeight.w700,
  );

  // ---------------------------------------------------------------------
  // Title — nombres de fila/tarjeta/canal.
  // ---------------------------------------------------------------------
  static const TextStyle titleDesktop = TextStyle(
    fontFamily: fontFamily,
    fontSize: 18,
    height: 24 / 18,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle titleTv = TextStyle(
    fontFamily: fontFamily,
    fontSize: 24,
    height: 32 / 24,
    fontWeight: FontWeight.w600,
  );

  // ---------------------------------------------------------------------
  // Body — metadatos, sinopsis.
  // ---------------------------------------------------------------------
  static const TextStyle bodyDesktop = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    height: 22 / 15,
    fontWeight: FontWeight.w400,
  );
  static const TextStyle bodyTv = TextStyle(
    fontFamily: fontFamily,
    fontSize: 18,
    height: 26 / 18,
    fontWeight: FontWeight.w400,
  );

  // ---------------------------------------------------------------------
  // Label — badges (DIRECTO/HD/5.1), timestamps, mayúsculas.
  // ---------------------------------------------------------------------
  static const TextStyle labelDesktop = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.24,
  );
  static const TextStyle labelTv = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    height: 18 / 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.24,
  );

  static TextStyle display(IptvDensity density) =>
      density == IptvDensity.tv ? displayTv : displayDesktop;
  static TextStyle headline(IptvDensity density) =>
      density == IptvDensity.tv ? headlineTv : headlineDesktop;
  static TextStyle title(IptvDensity density) =>
      density == IptvDensity.tv ? titleTv : titleDesktop;
  static TextStyle body(IptvDensity density) =>
      density == IptvDensity.tv ? bodyTv : bodyDesktop;
  static TextStyle label(IptvDensity density) =>
      density == IptvDensity.tv ? labelTv : labelDesktop;

  /// `TextTheme` de Material derivado de los 5 roles de arriba.
  ///
  /// Mapeo deliberado a los slots de `TextTheme` que la app ya consume hoy
  /// (`Theme.of(context).textTheme.headlineSmall` para títulos de fila,
  /// `.headlineMedium` para títulos de ficha, `.titleMedium` para nombres de
  /// tarjeta/canal, `.bodyMedium` para sinopsis/metadatos, `.labelMedium`
  /// para badges) — así las pantallas existentes reciben la tipografía
  /// correcta sin tener que reescribir cada punto de consumo; el resto de
  /// slots de `TextTheme` (`bodyLarge`, `bodySmall`, `titleLarge`, etc.) se
  /// heredan de la base de Material 3 y se reclasifican pantalla a pantalla
  /// según haga falta, no en este barrido de tokens.
  static TextTheme textTheme(Brightness brightness, {IptvDensity density = IptvDensity.desktop}) {
    final bodyColor = brightness == Brightness.dark ? IptvColors.textPrimary : null;
    final base = const TextTheme().apply(
      fontFamily: fontFamily,
      bodyColor: bodyColor,
      displayColor: bodyColor,
    );
    return base.copyWith(
      headlineSmall: display(density),
      headlineMedium: headline(density),
      titleMedium: title(density),
      bodyMedium: body(density),
      labelMedium: label(density),
    );
  }
}
