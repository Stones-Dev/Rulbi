import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_tokens/iptv_tokens.dart';

import '../../l10n/app_localizations.dart';
import '../../shell/tv_focusable.dart';
import 'player_controller.dart';

/// Panel lateral de canales rápidos para TV (Figma frame `45:22`, S9).
///
/// Se despliega sobre el reproductor al pulsar la tecla Menú / Lista en el mando.
/// Cumple la regla de foco de `ui-spec.md` §5.7: al abrirse, el foco se transfiere
/// directamente a la fila del canal activo en la cola (`autofocus: true`),
/// permitiendo zapping visual e inmediato sin interrumpir la reproducción.
class TvChannelDrawer extends StatefulWidget {
  const TvChannelDrawer({
    super.key,
    required this.controller,
    required this.onClose,
  });

  final PlayerController controller;
  final VoidCallback onClose;

  @override
  State<TvChannelDrawer> createState() => _TvChannelDrawerState();
}

class _TvChannelDrawerState extends State<TvChannelDrawer> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final queue = widget.controller.queue;
    final items = queue.items;
    final currentIndex = queue.index;

    return FocusScope(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.escape ||
              event.logicalKey == LogicalKeyboardKey.goBack ||
              event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            widget.onClose();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Align(
        alignment: Alignment.centerRight,
        child: Container(
          width: 440,
          height: double.infinity,
          decoration: BoxDecoration(
            color: IptvColors.surface.withValues(alpha: 0.96),
            border: const Border(
              left: BorderSide(
                color: IptvColors.border,
                width: 1.5,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 32,
                offset: const Offset(-8, 0),
              ),
            ],
          ),
          child: SafeArea(
            left: false,
            top: false,
            bottom: false,
            right: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Cabecera Figma 45:22
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 20,
                  ),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: IptvColors.border,
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.live_tv_rounded,
                        color: IptvColors.accent,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.navLiveTv,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    color: IptvColors.textPrimary,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${items.length} canales',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: IptvColors.textSecondary,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        'Back ✕',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: IptvColors.textSecondary,
                            ),
                      ),
                    ],
                  ),
                ),

                // Lista de canales
                Expanded(
                  child: ListView.separated(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final channel = items[index];
                      final isSelected = index == currentIndex;

                      return TvFocusable(
                        key: ValueKey('tv_drawer_channel_${channel.ref.key}'),
                        autofocus: isSelected,
                        onTap: () {
                          unawaited(widget.controller.jumpTo(index));
                        },
                        borderRadius: IptvSpacing.radius,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? IptvColors.accent.withValues(alpha: 0.18)
                                : Colors.transparent,
                            borderRadius:
                                BorderRadius.circular(IptvSpacing.radius),
                            border: isSelected
                                ? Border.all(
                                    color: IptvColors.accent,
                                    width: 1.5,
                                  )
                                : Border.all(
                                    color: Colors.transparent,
                                    width: 1.5,
                                  ),
                          ),
                          child: Row(
                            children: [
                              // Avatar / logo o número
                              _ChannelAvatar(channel: channel, index: index + 1),
                              const SizedBox(width: 14),

                              // Info del canal
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      channel.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: isSelected
                                            ? IptvColors.accent
                                            : IptvColors.textPrimary,
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.w500,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      channel.categoryId ?? 'General',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: IptvColors.textSecondary
                                            .withValues(alpha: 0.7),
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Indicador de reproducción actual
                              if (isSelected) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: IptvColors.accent,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.play_arrow_rounded,
                                        color: Colors.white,
                                        size: 14,
                                      ),
                                      SizedBox(width: 2),
                                      Text(
                                        'EN VIVO',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChannelAvatar extends StatelessWidget {
  const _ChannelAvatar({
    required this.channel,
    required this.index,
  });

  final Channel channel;
  final int index;

  @override
  Widget build(BuildContext context) {
    final logo = channel.logo?.toString();

    if (logo != null && logo.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: CachedNetworkImage(
          imageUrl: logo,
          width: 36,
          height: 36,
          fit: BoxFit.contain,
          placeholder: (_, _) => _FallbackNumber(index: index),
          errorWidget: (_, _, _) => _FallbackNumber(index: index),
        ),
      );
    }

    return _FallbackNumber(index: index);
  }
}

class _FallbackNumber extends StatelessWidget {
  const _FallbackNumber({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: IptvColors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: IptvColors.border),
      ),
      child: Text(
        '$index',
        style: const TextStyle(
          color: IptvColors.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
