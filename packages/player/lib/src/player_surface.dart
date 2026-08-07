import 'package:flutter/widgets.dart';
import 'package:media_kit_video/media_kit_video.dart' as mkv;

import 'media_kit_player.dart';

/// Superficie de vídeo (S6, Bloque A) — envuelve `Video` de `media_kit_video`
/// sobre el [MediaKitPlayer] pasado. Deliberadamente sin controles propios
/// de `media_kit_video` (`NoVideoControls`, D2 del plan): el overlay
/// (nombre, reloj, buffer, pistas, seek) lo pinta `PlayerOverlay` en
/// `apps/app`, encima de esta superficie — dos capas de overlay
/// competirían por los mismos gestos/teclado.
///
/// La relación de aspecto (ui-spec §2.13) es presentación, no una orden al
/// motor (D2): [fit] es el único punto de entrada, controlado por quien
/// use este widget.
class PlayerSurface extends StatelessWidget {
  const PlayerSurface({super.key, required this.player, this.fit = BoxFit.contain});

  final MediaKitPlayer player;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return mkv.Video(
      controller: player.videoController,
      fit: fit,
      // `null` = sin controles propios de media_kit_video (equivalente a
      // `mkv.NoVideoControls`, que la propia librería define como
      // `const NoVideoControls = null;` — se pasa el literal directo
      // porque ese `const` tipa como `dynamic` y no encaja en
      // `VideoControlsBuilder?`).
      controls: null,
    );
  }
}
