import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_tokens/iptv_tokens.dart';

import '../../l10n/app_localizations.dart';
import '../epg/epg_progress_bar.dart';
import '../epg/epg_providers.dart';
import '../favorites/favorites_providers.dart';
import '../sources/source_providers.dart';

/// Alto fijo de cada fila — `itemExtent` del `ListView.builder` del
/// listado virtualizado (S5 · Ola 1): con extent constante la barra de
/// desplazamiento es O(1) y representa los 100k canales reales.
const double channelRowExtent = 64;

/// Fila de canal (ui-spec §2.3): logo, nombre + EPG actual con barra de
/// progreso (S5 · Ola 2), y badge de favorito.
///
/// Foco visible (P9): anillo blanco + halo del acento, igual que
/// `TvShell` — esta fila debe ser navegable con teclado/D-pad desde el
/// primer commit, no como adaptación posterior.
class ChannelRow extends ConsumerStatefulWidget {
  const ChannelRow({
    super.key,
    required this.channel,
    this.highlightQuery,
    this.epgController,
    this.onTap,
  });

  final Channel channel;

  /// Si no es null, resalta la primera coincidencia (insensible a
  /// acentos/mayúsculas) dentro de [Channel.name] — búsqueda global
  /// (ui-spec §2.11: "resalta coincidencia"). `null` en el listado normal
  /// de canales, donde no hay una consulta que resaltar.
  final String? highlightQuery;

  /// `null` en contextos que no muestran EPG (p. ej. resultados de
  /// búsqueda, S5 · Ola 1) — sin controller, la fila no pinta subtítulo ni
  /// barra, el mismo estado "sin EPG" que un canal sin guía (S5 · Ola 2).
  final EpgNowController? epgController;

  /// Abre el canal (S6, Bloque E) — `null` no pinta ningún gesto de tap
  /// (ninguna pantalla actual deja esto sin cablear, pero el widget no
  /// debe asumirlo). El botón de favorito, dentro de la fila, sigue
  /// respondiendo a su propio tap sin activar este.
  final VoidCallback? onTap;

  @override
  ConsumerState<ChannelRow> createState() => _ChannelRowState();
}

class _ChannelRowState extends ConsumerState<ChannelRow> {
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
    final l10n = AppLocalizations.of(context);
    final textStyle = Theme.of(
      context,
    ).textTheme.bodyLarge?.copyWith(color: IptvColors.textPrimary);
    final epgController = widget.epgController;

    final favoriteRefsAsync = ref.watch(favoriteRefsProvider);
    final isFavorite =
        favoriteRefsAsync.valueOrNull?.contains(channel.ref) ?? false;

    // `InkWell` ya envuelve internamente un `Focus` propio — pasarle
    // `focusNode: _focusNode` en vez de anidar otro `Focus` explícito por
    // fuera (como antes de S6, Bloque E) evita dos `Focus` ancestros para
    // el mismo `Container`: con dos, `find.ancestor(matching:
    // find.byType(Focus)).first` de channel_list_screen_test.dart
    // encontraba el interno de `InkWell` (sin `_focusNode`, así que el
    // anillo nunca aparecía) en vez del que de verdad controla `_focused`.
    return InkWell(
      focusNode: _focusNode,
      onTap: widget.onTap,
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text.rich(
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
                  if (epgController != null)
                    EpgProgressBar(
                      tvgId: channel.tvgId,
                      controller: epgController,
                      channel: channel,
                    ),
                ],
              ),
            ),
            IconButton(
              key: Key('channelRow.favorite.${channel.ref.serialized}'),
              tooltip: isFavorite
                  ? l10n.favoriteRemoveTooltip
                  : l10n.favoriteAddTooltip,
              icon: Icon(
                isFavorite ? Icons.favorite : Icons.favorite_border,
                color: isFavorite
                    ? IptvColors.accent
                    : IptvColors.textSecondary,
              ),
              onPressed: () =>
                  ref.read(manageFavoritesProvider).toggle(channel.ref),
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
            Expanded(child: Container(height: 14, color: IptvColors.surface)),
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
