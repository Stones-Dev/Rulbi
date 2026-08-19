import 'dart:io';

import 'package:media_kit/media_kit.dart';

/// Arranque único de media_kit — debe llamarse una vez, antes de `runApp`
/// (S6, Bloque E: `main.dart` llama a esto, nunca a `MediaKit
/// .ensureInitialized()` directamente — P6, `apps/app` no importa
/// `media_kit`).
///
/// **Acotado a Windows/Linux desde S7 · Móvil base.** Verificado leyendo el
/// código fuente real de `media_kit` 1.2.6 (no de memoria, no había
/// dispositivo Android disponible para probarlo en caliente):
/// `NativeLibrary.ensureInitialized` (invocado por `MediaKit
/// .ensureInitialized`) hace `throw` explícito en Android cuando no
/// encuentra `libmpv.so`, y `MediaKit.ensureInitialized` lo propaga con
/// `rethrow` — no lo traga en silencio. Este paquete solo empaqueta
/// `media_kit_libs_windows_video`/`media_kit_libs_linux` (ver
/// `pubspec.yaml`); sin la guardia, llamar a esto desde `main()` (antes de
/// `runApp`, sin try/catch) crashearía la app entera al arrancar en
/// cualquier plataforma sin esas libs — Android incluido. El motor de
/// Android (media3) es alcance de S9; hasta entonces Android/webOS
/// simplemente no inicializan media_kit al arrancar.
final class IptvPlayback {
  const IptvPlayback._();

  /// [ensureInitialized] es inyectable para test — por defecto
  /// `MediaKit.ensureInitialized`, invocado solo cuando la plataforma actual
  /// empaqueta libmpv.
  static void ensureInitialized({
    void Function() ensureInitialized = MediaKit.ensureInitialized,
  }) {
    if (Platform.isWindows || Platform.isLinux) {
      ensureInitialized();
    }
  }
}
