import 'package:flutter/material.dart';
import 'package:iptv_core/iptv_core.dart' as core;
import 'package:media_kit_video/media_kit_video.dart' as mkv;

import 'android_media3_player.dart';
import 'android_media3_surface.dart';
import 'media_kit_player.dart';

/// Superficie de vídeo polimórfica (S9): renderiza la textura del motor nativo
/// correspondiente ([MediaKitPlayer] en Desktop vía libmpv, [AndroidMedia3Player]
/// en Android vía Media3 / ExoPlayer).
///
/// Deliberadamente sin controles propios del motor: el overlay propio lo pinta
/// `PlayerOverlay` en `apps/app`, encima de esta superficie (P6, ui-spec §2.13).
class PlayerSurface extends StatelessWidget {
  const PlayerSurface({
    super.key,
    required this.player,
    this.fit = BoxFit.contain,
  });

  final core.PlayerPort player;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final p = player;
    if (p is MediaKitPlayer) {
      return mkv.Video(
        controller: p.videoController,
        fit: fit,
        controls: null,
      );
    }
    if (p is AndroidMedia3Player) {
      return AndroidMedia3Surface(
        player: p,
        fit: fit,
      );
    }
    return const SizedBox.expand(
      child: ColoredBox(color: Colors.black),
    );
  }
}
