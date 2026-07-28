/// Escala de espaciado compartida por los tres shells (TV/Móvil/Desktop).
/// Base 4px; la TV tiende a usar los pasos más grandes (RNF-08, visibilidad
/// a distancia), el móvil y el desktop los intermedios/pequeños.
abstract final class IptvSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  /// Radio de esquina por defecto de tarjetas y controles.
  static const double radius = 12;
}
