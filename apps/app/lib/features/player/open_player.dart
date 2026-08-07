import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../home/home_providers.dart';
import 'playback_request.dart';
import 'player_screen.dart';

/// Única ruta de navegación al reproductor (S6, D4 del plan de la ola):
/// listado de canales, Home (continuar viendo/favoritos), Favoritos,
/// Búsqueda y las fichas VOD/Serie llaman **esto**, nunca
/// `Navigator.push(... PlayerScreen ...)` directamente — así hay un solo
/// sitio que decidir cómo se abre el reproductor (`Navigator` raíz que ya
/// provee `MaterialApp`, mismo patrón que `ContentDetailScreen`/
/// `ImportScreen`).
///
/// Al volver, invalida `continueWatchingProvider`: `PlayerController` ya
/// escribió `watch_state` real durante la reproducción (cada 10 s y al
/// salir), así que Home debe reflejarlo sin esperar a un rebuild
/// fortuito.
Future<void> openPlayer(BuildContext context, WidgetRef ref, PlaybackRequest request) async {
  await Navigator.of(
    context,
  ).push<void>(MaterialPageRoute(builder: (_) => PlayerScreen(request: request)));
  ref.invalidate(continueWatchingProvider);
}
