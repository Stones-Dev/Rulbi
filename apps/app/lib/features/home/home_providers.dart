import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iptv_core/iptv_core.dart';

import '../channels/channel_providers.dart';
import '../sources/source_providers.dart';

/// Home desktop — fila "Continuar viendo" (ui-spec §2.2, S5 · Ola 1). Desde
/// S6, `openPlayer` (`features/player/open_player.dart`) invalida este
/// provider al volver del reproductor — que sí escribe en `watch_state`
/// cada 10 s y al salir (`PlayerController`) — así que la fila se
/// refresca sin esperar a un rebuild fortuito.
final continueWatchingProvider = FutureProvider<List<ContinueWatchingItem>>((
  ref,
) {
  return ref.watch(getContinueWatchingProvider)();
});

/// Home desktop — fila "Ahora en tus canales" (ui-spec §2.2, S5 · Ola 2):
/// una muestra acotada de los canales en directo del usuario (no toda la
/// biblioteca, que puede ser 100k canales) — el mismo orden por nombre que
/// usa `ChannelListScreen`. `EpgProgressBar` decide fila a fila si hay algo
/// que mostrar; los canales sin guía sencillamente no aportan nada visible
/// en esta fila (sin dato inventado, RNF-09).
const int nowOnYourChannelsLimit = 10;

final nowOnYourChannelsProvider = FutureProvider<List<Channel>>((ref) {
  final sourceIds = ref.watch(activeSourceIdsProvider);
  return ref
      .watch(channelRepositoryProvider)
      .channelsPage(
        ChannelQuery(type: ContentType.live, sourceIds: sourceIds),
        offset: 0,
        limit: nowOnYourChannelsLimit,
      );
});
