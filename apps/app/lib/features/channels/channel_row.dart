import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_tokens/iptv_tokens.dart';

/// Alto fijo de cada fila — `itemExtent` del `ListView.builder` del
/// listado virtualizado (S5 · Ola 1): con extent constante la barra de
/// desplazamiento es O(1) y representa los 100k canales reales.
const double channelRowExtent = 64;

/// Fila de canal (ui-spec §2.3): logo, nombre, y hueco reservado para el
/// EPG actual + badge de favorito, que llegan en Ola 2 — de momento cada
/// fila se pinta "sin EPG" (uno de los estados que el propio ui-spec
/// contempla: "ítem sin subtítulo"), nunca con datos falsos.
///
/// Foco visible (P9): anillo blanco + halo del acento, igual que
/// `TvShell` — esta fila debe ser navegable con teclado/D-pad desde el
/// primer commit, no como adaptación posterior.
class ChannelRow extends StatefulWidget {
  const ChannelRow({super.key, required this.channel, this.highlightQuery});

  final Channel channel;

  /// Si no es null, resalta la primera coincidencia (insensible a
  /// acentos/mayúsculas) dentro de [Channel.name] — búsqueda global
  /// (ui-spec §2.11: "resalta coincidencia"). `null` en el listado normal
  /// de canales, donde no hay una consulta que resaltar.
  final String? highlightQuery;

  @override
  State<ChannelRow> createState() => _ChannelRowState();
}

class _ChannelRowState extends State<ChannelRow> {
  final FocusNode _focusNode = FocusNode();
  bool _focused = false;

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
    final channel = widget.channel;
    final textStyle = Theme.of(
      context,
    ).textTheme.bodyLarge?.copyWith(color: IptvColors.textPrimary);

    return Focus(
      focusNode: _focusNode,
      child: Container(
        key: Key('channelRow.${channel.ref.serialized}'),
        height: channelRowExtent,
        padding: const EdgeInsets.symmetric(horizontal: IptvSpacing.md),
        decoration: BoxDecoration(
          border: _focused ? IptvFocus.ring() : null,
          boxShadow: _focused ? IptvFocus.haloShadow() : null,
        ),
        child: Row(
          children: [
            _ChannelLogo(channel: channel),
            const SizedBox(width: IptvSpacing.md),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: highlightedSpans(
                    text: channel.name,
                    query: widget.highlightQuery,
                    baseStyle: textStyle,
                    matchStyle: textStyle?.copyWith(
                      color: IptvColors.accent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Esqueleto de fila mientras `ChannelPageCache` todavía no tiene la
/// página que cubre este índice — mismo `channelRowExtent`, para que el
/// scroll no salte cuando la página real llega.
class ChannelRowSkeleton extends StatelessWidget {
  const ChannelRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: channelRowExtent,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: IptvSpacing.md,
          vertical: IptvSpacing.md,
        ),
        child: Row(
          children: [
            const _LogoPlaceholder(),
            const SizedBox(width: IptvSpacing.md),
            Expanded(
              child: Container(height: 14, color: IptvColors.surface),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChannelLogo extends StatelessWidget {
  const _ChannelLogo({required this.channel});

  final Channel channel;

  @override
  Widget build(BuildContext context) {
    final logo = channel.logo;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: logo == null
          ? _LogoFallback(name: channel.name)
          : CachedNetworkImage(
              imageUrl: logo.toString(),
              width: 40,
              height: 40,
              fit: BoxFit.cover,
              // 2x el tamaño de layout: nítido en pantallas de alta
              // densidad sin decodificar el bitmap a resolución completa
              // del origen — con 100k filas potenciales en memoria de
              // caché de imagen, esto es lo que mantiene RNF-04 (< 300 MB)
              // bajo control.
              memCacheWidth: 80,
              memCacheHeight: 80,
              placeholder: (_, _) => _LogoFallback(name: channel.name),
              errorWidget: (_, _, _) => _LogoFallback(name: channel.name),
            ),
    );
  }
}

/// Muchos `tvg-logo` de listas M3U reales están rotos o ausentes — un
/// avatar con la inicial es mejor que un hueco vacío o un icono roto.
class _LogoFallback extends StatelessWidget {
  const _LogoFallback({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      color: IptvColors.surface,
      child: Text(
        initial,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(color: IptvColors.textSecondary),
      ),
    );
  }
}

class _LogoPlaceholder extends StatelessWidget {
  const _LogoPlaceholder();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Container(width: 40, height: 40, color: IptvColors.surface),
    );
  }
}

/// Resalta la primera coincidencia de [query] dentro de [text], insensible
/// a acentos/mayúsculas — reutiliza `normalizeForMatching` (`iptv_core`),
/// la misma normalización que el índice FTS5 espeja conceptualmente
/// (`packages/data/lib/src/db/fts.drift`), en vez de reinventar el
/// plegado de acentos en la capa de presentación.
///
/// Defensivo ante el único caso donde la normalización puede desalinear
/// índices con el texto original (`normalizeForMatching` recorta espacios
/// de los extremos): si el rango calculado no encaja en [text], se
/// devuelve sin resaltar en vez de arriesgar un `RangeError`.
List<InlineSpan> highlightedSpans({
  required String text,
  required String? query,
  required TextStyle? baseStyle,
  required TextStyle? matchStyle,
}) {
  final trimmedQuery = query?.trim() ?? '';
  if (trimmedQuery.isEmpty) return [TextSpan(text: text, style: baseStyle)];

  final normalizedText = normalizeForMatching(text);
  final normalizedQuery = normalizeForMatching(trimmedQuery);
  final start = normalizedText.indexOf(normalizedQuery);
  final end = start + normalizedQuery.length;
  if (start < 0 || end > text.length) {
    return [TextSpan(text: text, style: baseStyle)];
  }

  return [
    TextSpan(text: text.substring(0, start), style: baseStyle),
    TextSpan(text: text.substring(start, end), style: matchStyle),
    TextSpan(text: text.substring(end), style: baseStyle),
  ];
}
