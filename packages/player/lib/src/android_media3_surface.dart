import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'android_media3_player.dart';

/// Superficie de vídeo para Android (S9) sobre AndroidX Media3 (ExoPlayer).
///
/// Utiliza [VideoPlayer] con texturas nativas aceleradas por GPU, adaptándose
/// a cualquier [fit] (contain, cover, fill) mediante [FittedBox].
class AndroidMedia3Surface extends StatelessWidget {
  const AndroidMedia3Surface({
    super.key,
    required this.player,
    this.fit = BoxFit.contain,
  });

  final AndroidMedia3Player player;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final ctrl = player.controller;
        if (ctrl == null) {
          return const SizedBox.expand(
            child: ColoredBox(color: Colors.black),
          );
        }

        return ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: ctrl,
          builder: (context, value, _) {
            if (!value.isInitialized) {
              return const SizedBox.expand(
                child: ColoredBox(color: Colors.black),
              );
            }

            final size = value.size;
            final double aspectRatio = (size.width > 0 && size.height > 0)
                ? size.width / size.height
                : (value.aspectRatio > 0 ? value.aspectRatio : 16 / 9);

            return SizedBox.expand(
              child: FittedBox(
                fit: fit,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: size.width > 0 ? size.width : 1920,
                  height: size.height > 0 ? size.height : 1080,
                  child: AspectRatio(
                    aspectRatio: aspectRatio,
                    child: VideoPlayer(ctrl),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
