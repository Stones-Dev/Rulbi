import 'dart:io';

import 'package:iptv_core/iptv_core.dart' as core;
import 'package:media_kit/media_kit.dart';

import 'android_media3_player.dart';
import 'media_kit_player.dart';

/// Arranque único y factoría de reproducción — debe llamarse una vez, antes de `runApp`
/// (P6, `apps/app` no importa motores nativos directamente, solo `IptvPlayback`).
final class IptvPlayback {
  const IptvPlayback._();

  /// [ensureInitialized] es inyectable para test — por defecto
  /// `MediaKit.ensureInitialized`, invocado solo cuando la plataforma actual
  /// empaqueta libmpv (Windows/Linux).
  static void ensureInitialized({
    void Function() ensureInitialized = MediaKit.ensureInitialized,
  }) {
    if (Platform.isWindows || Platform.isLinux) {
      ensureInitialized();
    }
  }

  /// Factoría polimórfica de [core.PlayerPort] (P6, S9):
  /// - En Windows/Linux: [MediaKitPlayer] (libmpv en modo LGPL).
  /// - En Android/Android TV/Fire TV: [AndroidMedia3Player] (AndroidX Media3 ExoPlayer).
  static core.PlayerPort createPlayer() {
    if (Platform.isWindows || Platform.isLinux) {
      return MediaKitPlayer();
    }
    return AndroidMedia3Player();
  }
}

