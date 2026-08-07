import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_tokens/iptv_tokens.dart';

import '../../l10n/app_localizations.dart';
import '../epg/epg_progress_bar.dart';
import '../epg/epg_providers.dart';

/// Fila "Ahora en tus canales" de Home (ui-spec §2.2, S5 · Ola 2): EPG
/// actual con barra de progreso, mismo widget (`EpgProgressBar`) que
/// `ChannelRow` — no una segunda implementación de la barra. Un canal sin
/// guía sencillamente no aporta subtítulo/barra a su tarjeta (estado
/// vacío explícito, ver `EpgProgressBar`), nunca una tarjeta con datos
/// inventados.
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
          height: 236,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: channels.length,
            separatorBuilder: (_, _) => const SizedBox(width: IptvSpacing.lg),
            itemBuilder: (context, index) => _NowCard(
              channel: channels[index],
              epgController: epgController,
            ),
          ),
        ),
      ],
    );
  }
}

class _NowCard extends StatelessWidget {
  const _NowCard({required this.channel, required this.epgController});

  final Channel channel;
  final EpgNowController epgController;

  @override
  Widget build(BuildContext context) {
    final logo = channel.logo;

    return SizedBox(
      key: Key('nowOnYourChannels.${channel.ref.serialized}'),
      width: 310,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(IptvSpacing.radius),
            child: logo == null
                ? _PosterFallback(name: channel.name)
                : CachedNetworkImage(
                    imageUrl: logo.toString(),
                    width: 310,
                    height: 174,
                    fit: BoxFit.cover,
                    memCacheWidth: 620,
                    placeholder: (_, _) => _PosterFallback(name: channel.name),
                    errorWidget: (_, _, _) => _PosterFallback(name: channel.name),
                  ),
          ),
          const SizedBox(height: IptvSpacing.sm),
          Text(
            channel.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          EpgProgressBar(tvgId: channel.tvgId, controller: epgController, channel: channel),
        ],
      ),
    );
  }
}

class _PosterFallback extends StatelessWidget {
  const _PosterFallback({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 310,
      height: 174,
      alignment: Alignment.center,
      color: IptvColors.surface,
      child: Icon(
        Icons.live_tv_outlined,
        size: 40,
        color: IptvColors.textSecondary,
        semanticLabel: name,
      ),
    );
  }
}
