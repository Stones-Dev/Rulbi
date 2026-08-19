import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_tokens/iptv_tokens.dart';

// A diferencia de la versión anterior de este fichero (que evitaba probar
// IptvTheme.dark() porque disparaba la descarga en runtime de Inter vía
// google_fonts), desde S6.5 Inter va empaquetada como asset del propio
// paquete (packages/tokens/fonts/) — construir un ThemeData/TextTheme es
// una operación síncrona sobre datos Dart puros (no requiere que los bytes
// de la fuente estén cargados todavía), así que sí se prueba aquí.
// Lo que NO se prueba aquí es el renderizado real del glifo — eso sigue
// verificándose ejecutando la app (`flutter run -d windows`).

void main() {
  test('IptvColors reproduce el lenguaje visual de Figma', () {
    expect(IptvColors.background.toARGB32(), 0xFF0B0F14);
    expect(IptvColors.surface.toARGB32(), 0xFF151B24);
    expect(IptvColors.accent.toARGB32(), 0xFF3D7AFF);
  });

  test('IptvColors.onyx es la única paleta cableada, con los 4 campos de Figma', () {
    expect(IptvColors.onyx.background, IptvColors.background);
    expect(IptvColors.onyx.surface, IptvColors.surface);
    expect(IptvColors.onyx.accent, IptvColors.accent);
    expect(IptvColors.onyx.accentOn.toARGB32(), 0xFF06152F);
  });

  test('IptvFocus define el anillo blanco + halo fijado en Figma', () {
    expect(IptvFocus.ringColor.toARGB32(), 0xFFFFFFFF);
    expect(IptvFocus.haloShadow(), isNotEmpty);
    // Valor exacto del effect style "Elevation/Accent Halo" medido en
    // Figma (DROP_SHADOW, radius 24, spread 2) — no la aproximación previa.
    expect(IptvFocus.haloBlurRadius, 24);
    expect(IptvFocus.haloSpreadRadius, 2);
  });

  test('IptvSpacing sigue una escala base-8 creciente, con xxxl y los paddings de contenedor', () {
    const scale = [
      IptvSpacing.xs,
      IptvSpacing.sm,
      IptvSpacing.md,
      IptvSpacing.lg,
      IptvSpacing.xl,
      IptvSpacing.xxl,
      IptvSpacing.xxxl,
    ];
    for (var i = 1; i < scale.length; i++) {
      expect(scale[i], greaterThan(scale[i - 1]));
    }
    expect(IptvSpacing.xxxl, 64);
    expect(IptvSpacing.containerDesktop, 32);
    expect(IptvSpacing.safeAreaTv, 88);
  });

  test('IptvTypography define los 5 roles de ui-spec.md §5.1 para Desktop y TV', () {
    expect(IptvTypography.displayDesktop.fontSize, 28);
    expect(IptvTypography.displayDesktop.fontWeight, FontWeight.w700);
    expect(IptvTypography.displayTv.fontSize, 36);

    expect(IptvTypography.headlineDesktop.fontSize, 24);
    expect(IptvTypography.headlineTv.fontSize, 32);

    expect(IptvTypography.titleDesktop.fontSize, 18);
    expect(IptvTypography.titleDesktop.fontWeight, FontWeight.w600);
    expect(IptvTypography.titleTv.fontSize, 24);

    expect(IptvTypography.bodyDesktop.fontSize, 15);
    expect(IptvTypography.bodyTv.fontSize, 18);

    expect(IptvTypography.labelDesktop.fontSize, 12);
    expect(IptvTypography.labelDesktop.letterSpacing, 0.24);
    expect(IptvTypography.labelTv.fontSize, 14);

    // Todos los roles usan la familia empaquetada, no un passthrough de
    // Material 3 por defecto.
    for (final style in [
      IptvTypography.displayDesktop,
      IptvTypography.headlineDesktop,
      IptvTypography.titleDesktop,
      IptvTypography.bodyDesktop,
      IptvTypography.labelDesktop,
    ]) {
      expect(style.fontFamily, 'Inter');
    }
  });

  test('IptvTypography.textTheme mapea los 5 roles a los slots de Material que ya consume la app', () {
    final theme = IptvTypography.textTheme(Brightness.dark);
    expect(theme.headlineSmall?.fontSize, IptvTypography.displayDesktop.fontSize);
    expect(theme.headlineMedium?.fontSize, IptvTypography.headlineDesktop.fontSize);
    expect(theme.titleMedium?.fontSize, IptvTypography.titleDesktop.fontSize);
    expect(theme.bodyMedium?.fontSize, IptvTypography.bodyDesktop.fontSize);
    expect(theme.labelMedium?.fontSize, IptvTypography.labelDesktop.fontSize);
  });

  test('IptvTypography.textTheme con densidad TV usa el escalón de tamaño mayor', () {
    final theme = IptvTypography.textTheme(Brightness.dark, density: IptvDensity.tv);
    expect(theme.headlineSmall?.fontSize, IptvTypography.displayTv.fontSize);
    expect(theme.titleMedium?.fontSize, IptvTypography.titleTv.fontSize);
  });

  test('IptvTheme.dark() sin argumentos reproduce el comportamiento previo a S6.5', () {
    final theme = IptvTheme.dark();
    expect(theme.scaffoldBackgroundColor, IptvColors.background);
    expect(theme.colorScheme.surface, IptvColors.surface);
    expect(theme.colorScheme.primary, IptvColors.accent);
    expect(theme.textTheme.headlineSmall?.fontSize, IptvTypography.displayDesktop.fontSize);
  });

  test('IptvTheme.dark() acepta una paleta y densidad explícitas', () {
    const otherPalette = IptvColorPalette(
      background: Color(0xFF101419),
      surface: Color(0xFF1B1E1B),
      accent: Color(0xFFB4E61D),
      accentOn: Color(0xFF1D2405),
    );
    final theme = IptvTheme.dark(palette: otherPalette, density: IptvDensity.tv);
    expect(theme.scaffoldBackgroundColor, otherPalette.background);
    expect(theme.colorScheme.primary, otherPalette.accent);
    expect(theme.textTheme.headlineSmall?.fontSize, IptvTypography.displayTv.fontSize);
  });
}
