/// Tamaños de icono del lenguaje visual v2 (ui-spec.md §5.4).
///
/// El set en sí es Material Symbols Rounded (paquete `material_symbols_icons`,
/// re-exportado por `iptv_tokens.dart` para que baste un único import). Peso
/// uniforme 400, salvo estados activos (peso 600 + relleno) — mismo patrón
/// que el peso tipográfico de Title/Label.
abstract final class IptvIconSizes {
  /// Icono en línea con texto.
  static const double inline = 20;

  /// Icono de botón de acción.
  static const double action = 24;

  /// Icono en TV — D-pad-safe.
  static const double tv = 32;

  /// Icono hero (p. ej. el play grande del overlay del reproductor).
  static const double hero = 48;
}
