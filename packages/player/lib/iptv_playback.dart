/// `PlayerPort` y sus implementaciones por plataforma (media3, libmpv/libVLC,
/// AVPlayer, webOS). Único paquete del monorepo con permiso de importar un
/// SDK de reproducción nativo — ver principio P6 en `.specify/constitution.md`.
///
/// S6 añade la implementación de escritorio (Windows/Linux): [MediaKitPlayer]
/// sobre media_kit/libmpv (ADR-009), [PlayerSurface] (widget de vídeo) e
/// [IptvPlayback] (arranque único de media_kit desde `main.dart`).
library;

export 'src/media_kit_player.dart';
export 'src/player_surface.dart';
export 'src/playback_bootstrap.dart';
