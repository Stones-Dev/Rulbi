/// Escala de espaciado compartida por los tres shells (TV/Móvil/Desktop).
/// Base 8px (ui-spec.md §5.2, S6.5) — los gaps ya en uso en el boceto
/// (24/52/88px) son múltiplos de 8. La TV tiende a usar los pasos más
/// grandes (RNF-08, visibilidad a distancia), el móvil y el desktop los
/// intermedios/pequeños.
abstract final class IptvSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
  static const double xxxl = 64;

  /// Padding de contenedor de pantalla en Desktop (ui-spec.md §5.2).
  static const double containerDesktop = 32;

  /// Padding de contenedor de pantalla en TV — distancia de visión + safe
  /// area de televisores (ui-spec.md §5.2).
  static const double safeAreaTv = 88;

  /// Padding de contenedor de pantalla en Móvil (S7 · Móvil base).
  /// **`ui-spec.md §5.2` no define todavía una columna Mobile** — propuesta
  /// con criterio explícito, no decisión de diseño cerrada (mismo hueco que
  /// `IptvDensity.mobile`, ver su docstring). 32px (el valor de Desktop) se
  /// comerían el 18% del ancho útil en una pantalla de 360dp.
  static const double containerMobile = 16;

  /// Radio de esquina por defecto de tarjetas y controles.
  ///
  /// Nota (S6.5, Implementación Desktop rediseñado): los frames de Figma ya
  /// fusionados usan más de un valor de radio según el elemento (6 en
  /// pósters, 8-10 en tarjetas, 12 en rail/pills). Formalizar una escala de
  /// radios requiere antes enmendar `ui-spec.md §5.2` (que hoy solo define
  /// la escala de espaciado, no de radios) — no se ha hecho todavía, así
  /// que este token se deja como estaba, sin ampliar sin pasar por el vault.
  static const double radius = 12;
}
