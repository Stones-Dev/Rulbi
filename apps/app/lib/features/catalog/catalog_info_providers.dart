import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_protocols/iptv_protocols.dart';

import '../sources/source_providers.dart';

/// Fábrica del transporte HTTP del `XtreamClient` de esta pantalla — mismo
/// criterio que `xtreamProbeProvider`/`XtreamEpgFallback.clientFactory`:
/// se construye de nuevo en cada llamada, nunca compartido entre fichas.
/// Provider propio (en vez de inline en `_xtreamClientFor`) para que
/// `vod_detail_screen_test.dart`/`series_detail_screen_test.dart` puedan
/// sustituirlo por un transporte falso sin red real.
final xtreamInfoTransportFactoryProvider = Provider<XtreamTransport Function()>((ref) {
  return () => RetryingXtreamTransport(HttpXtreamTransport());
});

/// Ficha completa VOD/Serie (ui-spec §2.6/§2.7, S6, Bloque D):
/// `get_vod_info`/`get_series_info` bajo demanda, con caché. `family`
/// sobre [Channel] entero (no sobre un `id` suelto, como sugiere la
/// redacción de ui-spec) porque resolver el panel exige `sourceId` **y**
/// `x-xtream-stream-id`/`x-xtream-series-id` a la vez, y la pantalla ya
/// tiene el `Channel` completo en la mano — `Channel` implementa
/// `==`/`hashCode`, así que la clave de caché es estable.
///
/// `FutureProvider.family` sin `autoDispose`: caché por sesión de app,
/// mismo patrón que `channelCountProvider`/`categoriesWithCountProvider`
/// (`channel_providers.dart`) — es la "caché" que pide §2.6/§2.7, nunca
/// una precarga del catálogo (cada ficha se resuelve solo cuando se abre).
///
/// `null` = no hay ficha que mostrar (fuente no Xtream, sin credencial
/// guardada, o el panel falló) — la pantalla cae al fallback tipográfico
/// digno que ya pintaba `ContentDetailScreen` (S5.5), nunca un error.
final vodInfoProvider = FutureProvider.family<XtreamVodInfo?, Channel>((ref, channel) async {
  final streamId = channel.metadata['x-xtream-stream-id'];
  if (streamId == null) return null;

  final client = await _xtreamClientFor(ref, channel);
  if (client == null) return null;

  final result = await client.vodInfo(streamId);
  return result is XtreamOk<XtreamVodInfo> ? result.value : null;
});

final seriesInfoProvider = FutureProvider.family<XtreamSeriesInfo?, Channel>((ref, channel) async {
  final seriesId = channel.metadata['x-xtream-series-id'];
  if (seriesId == null) return null;

  final client = await _xtreamClientFor(ref, channel);
  if (client == null) return null;

  final result = await client.seriesInfo(seriesId);
  return result is XtreamOk<XtreamSeriesInfo> ? result.value : null;
});

/// `null` = fuente no Xtream, ya no existe, o sin credencial guardada —
/// mismo criterio de "no reproducible" que `PlaybackUrlResolver`
/// (`features/player/playback_url_resolver.dart`), aplicado aquí a "no
/// hay ficha ampliada".
Future<XtreamClient?> _xtreamClientFor(Ref ref, Channel channel) async {
  final source = await ref.watch(sourceRepositoryProvider).getById(channel.sourceId);
  final config = source?.config;
  if (config is! XtreamSourceConfig) return null;

  final secret = await ref.watch(secureCredentialStoreProvider).read(channel.sourceId);
  if (secret == null) return null;

  return XtreamClient(
    host: config.host,
    username: config.username,
    password: secret,
    transport: ref.watch(xtreamInfoTransportFactoryProvider)(),
  );
}
