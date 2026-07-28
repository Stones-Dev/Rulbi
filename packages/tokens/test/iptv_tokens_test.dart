import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_tokens/iptv_tokens.dart';

// La construcción de IptvTheme.dark() (que dispara la carga de la fuente
// Inter vía google_fonts) se verifica ejecutando la app, no aquí: cargar
// fuentes en el entorno de `flutter test` es asíncrono y frágil sin bundlear
// los .ttf de test (ver README de google_fonts). Ver verificación de S0:
// `flutter run -d windows` debe mostrar el DesktopShell con estos tokens.

void main() {
  test('IptvColors reproduce el lenguaje visual de Figma', () {
    expect(IptvColors.background.toARGB32(), 0xFF0B0F14);
    expect(IptvColors.surface.toARGB32(), 0xFF151B24);
    expect(IptvColors.accent.toARGB32(), 0xFF3D7AFF);
  });

  test('IptvFocus define el anillo blanco + halo fijado en Figma', () {
    expect(IptvFocus.ringColor.toARGB32(), 0xFFFFFFFF);
    expect(IptvFocus.haloShadow(), isNotEmpty);
  });

  test('IptvSpacing sigue una escala base-4 creciente', () {
    const scale = [
      IptvSpacing.xs,
      IptvSpacing.sm,
      IptvSpacing.md,
      IptvSpacing.lg,
      IptvSpacing.xl,
      IptvSpacing.xxl,
    ];
    for (var i = 1; i < scale.length; i++) {
      expect(scale[i], greaterThan(scale[i - 1]));
    }
  });
}
