import 'package:flutter/material.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_tokens/iptv_tokens.dart';

import '../../l10n/app_localizations.dart';
import '../../widgets/media_card.dart';
import '../epg/epg_progress_bar.dart';
import '../epg/epg_providers.dart';

/// Fila "Ahora en tus canales" de Home (ui-spec §2.2, S5 · Ola 2): EPG
/// actual con barra de progreso, mismo widget (`EpgProgressBar`) que
/// `ChannelRow` — no una segunda implementación de la barra. Un canal sin
/// guía sencillamente no aporta subtítulo/barra a su tarjeta (estado
/// vacío explícito, ver `EpgProgressBar`), nunca una tarjeta con datos
/// inventados.
///
/// S6.5 (Implementación Desktop rediseñado): `MediaCard` + insignia "EN
/// DIRECTO" (frame canónico `38:3`, `Row/AhoraEnTusCanales` → `LiveBadge`)
/// en azul de acento — el mockup de Python la tenía en rojo, corregido en
/// la propia revisión de Figma (`48:2`, caption `54:35`) antes de fusionar.
class NowOnYourChannelsRow extends StatelessWidget {
  const NowOnYourChannelsRow({
    super.key,
    required this.channels,
    required this.epgController,
  });

  final List<Channel> channels;
  final EpgNowController epgController;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.homeNowOnYourChannelsTitle,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: IptvSpacing.md),
        SizedBox(
          height: MediaCard.height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: channels.length,
            separatorBuilder: (_, _) => const SizedBox(width: IptvSpacing.lg),
            itemBuilder: (context, index) {
              final channel = channels[index];
              return MediaCard(
                itemKey: Key('nowOnYourChannels.${channel.ref.serialized}'),
                imageUrl: channel.logo,
                fallbackLabel: channel.name,
                fallbackIcon: Symbols.live_tv_rounded,
                title: channel.name,
                badge: _LiveBadge(label: l10n.homeLiveBadge),
                footer: EpgProgressBar(tvgId: channel.tvgId, controller: epgController, channel: channel),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: IptvSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: IptvColors.accent,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: IptvTypography.labelDesktop.copyWith(color: IptvColors.onyx.accentOn)),
    );
  }
}
