import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:iptv_tokens/iptv_tokens.dart';

import '../l10n/app_localizations.dart';
import 'poster_fallback.dart';

/// Cabecera compartida de las fichas de detalle (VOD `43:2`, Serie `44:2`,
/// S6.5 pasos 7/8): backdrop a sangre con scrim, botón de volver circular
/// flotante, y un póster que solapa el borde inferior del backdrop.
/// Sustituye el `AppBar` + póster centrado que tenían ambas fichas antes
/// del rediseño — decisión tomada con el usuario (backdrop a sangre, sin
/// `AppBar`).
///
/// El [content] (título/meta/sinopsis/CTA, o cabecera+chips+lista en
/// series) se coloca **debajo** de todo el bloque backdrop+póster, no al
/// lado del póster como en el mockup de Figma — a diferencia de los
/// títulos de demo (una o dos líneas fijas), una sinopsis real puede ser
/// arbitrariamente larga; envolverla junto al póster sin desbordarlo de
/// forma robusta para cualquier longitud de texto no es viable sin
/// recortar contenido real. El tratamiento visual (backdrop, scrim,
/// póster solapado) es el mismo; solo cambia dónde arranca el texto.
class DetailHero extends StatelessWidget {
  const DetailHero({
    super.key,
    required this.title,
    required this.content,
    this.backdropUrl,
    this.coverUrl,
    this.heroTag,
    this.backdropHeight = 340,
    this.posterWidth = 160,
    this.posterHeight = 230,
    this.posterOverlap = 50,
  });

  /// Usado como texto del fallback del póster/backdrop y como
  /// `semanticLabel` por defecto.
  final String title;

  /// Título/meta/sinopsis/CTA (VOD) o esa misma cabecera + chips de
  /// temporada + lista de episodios (Serie) — lo que va debajo del hero.
  final Widget content;

  final String? backdropUrl;
  final String? coverUrl;

  /// `null` no envuelve el póster en `Hero` — no todos los orígenes
  /// (`MediaCard`/`PosterCard`) propagan un tag (paso 7e).
  final String? heroTag;

  /// Alto del backdrop — `480` en el frame VOD `43:2`, `340` (el valor por
  /// defecto) en el frame Serie `44:2`.
  final double backdropHeight;

  /// Tamaño del póster — `180×260` en VOD, `160×230` (por defecto) en
  /// Serie.
  final double posterWidth;
  final double posterHeight;

  /// Cuánto del póster queda DENTRO del backdrop (el resto cuelga por
  /// debajo) — `60` en VOD, `50` (por defecto) en Serie. Medido en Figma:
  /// `posterTop = backdropHeight - posterOverlap`.
  final double posterOverlap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hangingHeight = posterHeight - posterOverlap;

    Widget poster = ClipRRect(
      borderRadius: BorderRadius.circular(IptvSpacing.radius),
      child: SizedBox(
        width: posterWidth,
        height: posterHeight,
        child: _PosterImage(title: title, coverUrl: coverUrl),
      ),
    );
    final tag = heroTag;
    if (tag != null) poster = Hero(tag: tag, child: poster);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            SizedBox(
              width: double.infinity,
              height: backdropHeight,
              child: _Backdrop(backdropUrl: backdropUrl, coverUrl: coverUrl),
            ),
            Positioned(
              left: IptvSpacing.xl,
              top: IptvSpacing.xl,
              child: _CircleBackButton(tooltip: l10n.playerBackTooltip),
            ),
            Positioned(left: IptvSpacing.xl, top: backdropHeight - posterOverlap, child: poster),
          ],
        ),
        SizedBox(height: hangingHeight + IptvSpacing.lg),
        content,
      ],
    );
  }
}

class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.backdropUrl, required this.coverUrl});

  final String? backdropUrl;
  final String? coverUrl;

  @override
  Widget build(BuildContext context) {
    final backdrop = backdropUrl;
    final cover = coverUrl;

    Widget image;
    if (backdrop != null) {
      image = CachedNetworkImage(
        imageUrl: backdrop,
        fit: BoxFit.cover,
        placeholder: (_, _) => const ColoredBox(color: IptvColors.surface),
        errorWidget: (_, _, _) => const ColoredBox(color: IptvColors.surface),
      );
    } else if (cover != null) {
      // Sin backdrop real (panel que no lo trae): el póster difuminado y
      // escalado hace de fondo, en vez de dejar la franja superior vacía.
      image = Transform.scale(
        scale: 1.15,
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30, tileMode: TileMode.decal),
          child: CachedNetworkImage(
            imageUrl: cover,
            fit: BoxFit.cover,
            placeholder: (_, _) => const ColoredBox(color: IptvColors.surface),
            errorWidget: (_, _, _) => const ColoredBox(color: IptvColors.surface),
          ),
        ),
      );
    } else {
      image = const ColoredBox(color: IptvColors.surface);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        image,
        // Scrim de legibilidad hasta el fondo opaco — para que el póster y
        // el contenido de debajo no queden a medio camino entre backdrop e
        // interfaz (misma receta que el scrim de `MediaCard`, más alto).
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0.0, 0.55, 1.0],
              colors: [Color(0x000B0F14), Color(0x000B0F14), IptvColors.background],
            ),
          ),
        ),
      ],
    );
  }
}

class _PosterImage extends StatelessWidget {
  const _PosterImage({required this.title, required this.coverUrl});

  final String title;
  final String? coverUrl;

  @override
  Widget build(BuildContext context) {
    final url = coverUrl;
    if (url == null) return PosterFallback(name: title);
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      memCacheWidth: 480,
      placeholder: (_, _) => PosterFallback(name: title),
      errorWidget: (_, _, _) => PosterFallback(name: title),
    );
  }
}

class _CircleBackButton extends StatelessWidget {
  const _CircleBackButton({required this.tooltip});

  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: IptvColors.surface.withValues(alpha: 0.7),
      shape: const CircleBorder(),
      child: IconButton(
        key: const Key('contentDetail.back'),
        tooltip: tooltip,
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Symbols.arrow_back_rounded, color: IptvColors.textPrimary),
        iconSize: IptvIconSizes.action,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      ),
    );
  }
}
