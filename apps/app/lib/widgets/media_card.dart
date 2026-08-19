import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:iptv_tokens/iptv_tokens.dart';

/// Tarjeta de medio compartida (S6.5, Implementación Desktop rediseñado) —
/// consolida las 3 implementaciones antes independientes de
/// `_ContinueWatchingCard`/`_FavoriteCard`/`_NowCard`
/// (`features/home/*_row.dart`), cada una con su propio fallback de imagen
/// y sin degradado ni halo de hover.
///
/// Medidas y layout — imagen a sangre completa 220×124 con título/progreso
/// superpuestos sobre un degradado inferior — son las del frame canónico
/// `Desktop / Home` (`38:3`) ya fusionado en Figma, no un valor elegido
/// aquí: `Card/*` mide 220×124, el título se ancla a y=86-90 (dentro de la
/// franja de degradado) y la barra de progreso a y=110.
///
/// El halo de acento (`IptvFocus`) se dispara en foco **y** en hover/pressed
/// en Desktop (ui-spec.md §5.3) — antes solo cubría foco por teclado/mando.
/// Deliberadamente no se usa aquí en `PosterCard`/`ChannelRow`
/// (`catalog/poster_card.dart`, `channels/channel_row.dart`): esas
/// pantallas no forman parte de las 5 fusionadas en esta tarea.
class MediaCard extends StatefulWidget {
  const MediaCard({
    super.key,
    this.itemKey,
    required this.imageUrl,
    required this.fallbackLabel,
    this.fallbackIcon = Symbols.movie_rounded,
    this.title,
    this.badge,
    this.progress,
    this.footer,
    this.onTap,
    this.semanticLabel,
    this.heroTag,
  });

  /// Tamaño exacto del frame canónico `Card/*` de `38:3` — único en toda la
  /// app, para que las 3 filas de Home no repitan el número por su cuenta.
  static const double width = 220;
  static const double height = 124;

  /// Altura de la franja de degradado inferior, medida desde el borde
  /// inferior de la tarjeta — cubre el título (y=86-110) con margen.
  static const double _scrimHeight = 70;

  /// Identificador de fila/canal/ref — reemplaza los
  /// `Key('continueWatching.&lt;ref&gt;')`/`Key('favoritesRow.&lt;ref&gt;')`/
  /// `Key('nowOnYourChannels.&lt;ref&gt;')` previos; cada fila sigue
  /// componiendo su propia clave con prefijo, esta tarjeta solo la recibe.
  final Key? itemKey;

  final Uri? imageUrl;

  /// Nombre del canal/título — usado tanto como texto del fallback (sin
  /// imagen) como `semanticLabel` por defecto.
  final String fallbackLabel;

  /// Icono del fallback cuando no hay [imageUrl] o falla la carga. Distinto
  /// por fila (película/serie vs. directo) en las 3 filas de Home — antes
  /// cada una llevaba su propio `_PosterFallback` solo para variar esto.
  final IconData fallbackIcon;

  /// Título superpuesto sobre el degradado — `null` omite el título (p. ej.
  /// si el propio [footer] ya lo incluye).
  final String? title;

  /// Insignia superpuesta arriba a la izquierda de la imagen (p. ej. "EN
  /// DIRECTO"). `null` no pinta nada.
  final Widget? badge;

  /// Fracción 0..1 pintada como barra fina en el borde inferior. `null` no
  /// pinta barra (p. ej. directo, o un favorito sin progreso).
  final double? progress;

  /// Contenido adicional bajo el título, dentro de la franja de degradado
  /// (p. ej. tiempo restante, o `EpgProgressBar` — un widget reactivo, no
  /// solo texto estático). `null` no añade nada.
  final Widget? footer;

  final VoidCallback? onTap;

  /// `null` usa [fallbackLabel].
  final String? semanticLabel;

  /// Propaga la transición `Hero` hacia el póster de la ficha de detalle
  /// (S6.5 paso 7e, nodo Figma `43:15`) — `null` no envuelve la imagen en
  /// `Hero` (no todos los orígenes de `MediaCard` navegan a una ficha con
  /// póster que la reciba, p. ej. "Continuar viendo" abre el reproductor
  /// directo). Cuando se usa, debe ser la misma cadena que recibe
  /// `VodDetailScreen.heroTag`/`SeriesDetailScreen.heroTag` en el destino.
  final String? heroTag;

  @override
  State<MediaCard> createState() => _MediaCardState();
}

class _MediaCardState extends State<MediaCard> {
  final FocusNode _focusNode = FocusNode();
  bool _focused = false;
  bool _hovering = false;
  bool _pressed = false;

  bool get _highlighted => _focused || _hovering || _pressed;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChange);
  }

  void _handleFocusChange() => setState(() => _focused = _focusNode.hasFocus);

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final tag = widget.heroTag;
    final image = _Image(
      imageUrl: widget.imageUrl,
      fallbackLabel: widget.fallbackLabel,
      fallbackIcon: widget.fallbackIcon,
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Semantics(
        label: widget.semanticLabel ?? widget.fallbackLabel,
        button: widget.onTap != null,
        child: InkWell(
          focusNode: _focusNode,
          onTap: widget.onTap,
          onHighlightChanged: (pressed) => setState(() => _pressed = pressed),
          borderRadius: BorderRadius.circular(IptvSpacing.radius),
          child: Container(
            key: widget.itemKey,
            width: MediaCard.width,
            height: MediaCard.height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(IptvSpacing.radius),
              border: _highlighted ? IptvFocus.ring() : null,
              boxShadow: _highlighted ? IptvFocus.haloShadow() : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(IptvSpacing.radius),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  tag != null ? Hero(tag: tag, child: image) : image,
                  if (widget.title != null || widget.footer != null) _Scrim(),
                  if (widget.badge != null)
                    Positioned(top: IptvSpacing.xs, left: IptvSpacing.xs, child: widget.badge!),
                  if (widget.title != null || widget.footer != null)
                    Positioned(
                      left: IptvSpacing.sm,
                      right: IptvSpacing.sm,
                      bottom: widget.progress != null ? IptvSpacing.md : IptvSpacing.sm,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (widget.title != null)
                            Text(
                              widget.title!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.titleMedium?.copyWith(color: IptvColors.textPrimary),
                            ),
                          if (widget.footer != null) widget.footer!,
                        ],
                      ),
                    ),
                  if (widget.progress != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(IptvSpacing.radius)),
                        child: LinearProgressIndicator(
                          value: widget.progress,
                          minHeight: 4,
                          backgroundColor: IptvColors.border,
                          valueColor: const AlwaysStoppedAnimation(IptvColors.accent),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Image extends StatelessWidget {
  const _Image({required this.imageUrl, required this.fallbackLabel, required this.fallbackIcon});

  final Uri? imageUrl;
  final String fallbackLabel;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url == null) return _Fallback(label: fallbackLabel, icon: fallbackIcon);
    return CachedNetworkImage(
      imageUrl: url.toString(),
      fit: BoxFit.cover,
      // 2x-ish el ancho de layout — nítido en pantallas de alta densidad
      // sin decodificar el bitmap a resolución completa del origen (mismo
      // criterio RNF-04 que el resto de imágenes cacheadas de la app).
      memCacheWidth: (MediaCard.width * 2).round(),
      placeholder: (_, _) => _Fallback(label: fallbackLabel, icon: fallbackIcon),
      errorWidget: (_, _, _) => _Fallback(label: fallbackLabel, icon: fallbackIcon),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: IptvColors.surface,
      child: Center(
        child: Icon(icon, size: IptvIconSizes.action, color: IptvColors.textSecondary, semanticLabel: label),
      ),
    );
  }
}

/// Degradado inferior de legibilidad — añadido en la fusión de Figma
/// (`48:2`→`38:3`/`41:2`), ninguna tarjeta lo tenía antes de S6.5. Mismo
/// valor de alfa (~85%) que se aplicó en Figma vía `use_figma`.
class _Scrim extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        height: MediaCard._scrimHeight,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x000B0F14), Color(0xD90B0F14)], // transparente -> background ~85%
          ),
        ),
      ),
    );
  }
}
