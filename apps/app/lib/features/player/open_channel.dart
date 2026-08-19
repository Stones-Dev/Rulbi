import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iptv_core/iptv_core.dart';

import '../catalog/series_detail_screen.dart';
import '../catalog/vod_detail_screen.dart';
import 'open_player.dart';
import 'playback_request.dart';

/// Qué pasa al tocar un [Channel] en un contexto que mezcla tipos —
/// Favoritos, Búsqueda (S6, Bloque E). Mismo despacho por [ContentType]
/// que ya usa `CatalogScreen._openDetail` (S5.5, D6): directo abre el
/// reproductor (D4 — vía [openPlayer], la única ruta), película/serie
/// abren su ficha completa (ui-spec §2.6/§2.7). `CatalogScreen` no
/// reutiliza esto porque nunca ve `ContentType.live` (separa Películas/
/// Series en pestañas propias) — aquí sí hace falta el `switch` completo.
Future<void> openChannel(
  BuildContext context,
  WidgetRef ref,
  Channel channel, {
  PlaybackQueue? queue,
  Duration startAt = Duration.zero,
  // S6.5 paso 7e: propagado hasta `VodDetailScreen`/`SeriesDetailScreen`
  // para que su póster haga una transición `Hero` desde la tarjeta de
  // origen. `null` (por defecto) no envuelve nada en `Hero` — el directo
  // no tiene ficha a la que emparejar.
  String? heroTag,
}) {
  switch (channel.type) {
    case ContentType.live:
      return openPlayer(context, ref, PlaybackRequest(channel: channel, startAt: startAt, queue: queue));
    case ContentType.vod:
      return Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => VodDetailScreen(channel: channel, heroTag: heroTag)),
      );
    case ContentType.series:
      return Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => SeriesDetailScreen(channel: channel, heroTag: heroTag)),
      );
  }
}
