import 'package:media_kit/media_kit.dart';

/// Arranque único de media_kit — debe llamarse una vez, antes de `runApp`
/// (S6, Bloque E: `main.dart` llama a esto, nunca a `MediaKit
/// .ensureInitialized()` directamente — P6, `apps/app` no importa
/// `media_kit`).
final class IptvPlayback {
  const IptvPlayback._();

  static void ensureInitialized() => MediaKit.ensureInitialized();
}
