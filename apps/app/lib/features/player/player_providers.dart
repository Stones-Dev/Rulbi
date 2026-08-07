import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_playback/iptv_playback.dart';

import '../sources/source_providers.dart';
import 'playback_url_resolver.dart';

/// `PlaybackUrlResolver` (S6, Bloque B): compone `sourceRepositoryProvider`
/// + `secureCredentialStoreProvider`, ya construidos y compartidos por el
/// resto de la app — mismo criterio que `xtreamEpgFallbackProvider`
/// (`features/epg/epg_providers.dart`), que compone exactamente los mismos
/// dos puertos más uno.
final playbackUrlResolverProvider = Provider<PlaybackUrlResolver>((ref) {
  return PlaybackUrlResolver(
    sources: ref.watch(sourceRepositoryProvider),
    secureStore: ref.watch(secureCredentialStoreProvider),
  );
});

/// `MediaKitPlayer` **no** se cablea como `Provider.autoDispose` (a
/// diferencia de lo esbozado en la fase de plan de esta ola) — mismo
/// criterio que `createEpgNowController`
/// (`features/epg/epg_providers.dart`): una instancia por pantalla, con
/// ciclo de vida atado al `State` que la usa (`initState`/`dispose`), no
/// al árbol de providers. Un `Provider.autoDispose` que nadie vuelve a
/// `ref.watch` en cada rebuild se libera solo al final del mismo frame en
/// que se lee (`ref.read`) — encaja mal con un recurso que debe vivir
/// mientras dura `PlayerScreen`, no mientras algo lo observe activamente.
/// Desviación declarada en el handoff de S6.
///
/// Tipado como [PlayerPort] (no [MediaKitPlayer]) a propósito: es el punto
/// de inyección que `player_screen_test.dart` sustituye por un
/// `FakePlayerPort` (`PlayerScreen.createPort`, S6, Bloque C) — el mismo
/// motivo por el que `MediaKitPlayer` no es testeable en CI sin libmpv
/// nativo no debe contagiar a los atajos/overlay, que sí lo son.
PlayerPort createPlayerPort() => MediaKitPlayer();
