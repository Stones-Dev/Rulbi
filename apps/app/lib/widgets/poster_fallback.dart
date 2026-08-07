import 'package:flutter/material.dart';
import 'package:iptv_tokens/iptv_tokens.dart';

/// Fallback tipográfico para un póster sin imagen — nombre centrado sobre
/// `IptvColors.surface`, en vez de un hueco vacío o un icono roto. Muchos
/// `tvg-logo`/`stream_icon`/`cover` de fuentes reales están rotos o
/// ausentes (mismo criterio que `_LogoFallback` de `channel_row.dart`,
/// pero cuadrado en vez de circular/40px — el formato de un póster).
///
/// Compartido entre `FavoritesRow` (Home) y `PosterCard` (S5.5, listado de
/// Películas/Series, ui-spec §2.3.1/§2.6) — antes duplicado, ver
/// `favorites_row.dart`.
class PosterFallback extends StatelessWidget {
  const PosterFallback({super.key, required this.name, this.size});

  final String name;

  /// `null` deja que el padre (un `SizedBox`/`AspectRatio`) decida el
  /// tamaño — `FavoritesRow` fija 174×174, `PosterCard` varía con el
  /// ancho de la rejilla.
  final double? size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      color: IptvColors.surface,
      padding: const EdgeInsets.all(IptvSpacing.sm),
      child: Text(
        name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(color: IptvColors.textSecondary),
      ),
    );
  }
}
