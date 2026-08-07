import 'package:iptv_core/iptv_core.dart';

/// Ventana ordenada de canales/episodios sobre la que ↑/↓ zapean dentro del
/// reproductor (S6, Bloque C, D3 del plan de la ola). Deliberadamente
/// **sin** conocimiento de dónde viene [items] — el listado paginado de
/// canales pasa la página cargada que contenía el canal tocado
/// (`ChannelPageCache.loadedWindowAround`), una serie pasa la lista de
/// episodios de la temporada abierta, y Favoritos/Búsqueda pasan lo que
/// tengan ya en memoria. Sin cola (`PlaybackRequest.queue == null`), ↑/↓
/// no hacen nada — nunca se inventa una cola de un solo elemento.
final class PlaybackQueue {
  const PlaybackQueue({required this.items, required this.index})
    : assert(items.length > 0, 'una cola vacía no es una cola'),
      assert(index >= 0 && index < items.length, 'index fuera de rango');

  final List<Channel> items;
  final int index;

  Channel get current => items[index];
  bool get hasPrevious => index > 0;
  bool get hasNext => index < items.length - 1;

  /// Nueva cola con [index] desplazado por [delta], recortado a los
  /// extremos (D3: "se detienen en los extremos", nunca da la vuelta).
  PlaybackQueue advance(int delta) {
    final next = (index + delta).clamp(0, items.length - 1);
    return PlaybackQueue(items: items, index: next);
  }
}

/// Lo que hace falta para abrir el reproductor (S6, Bloque C, D4 del plan:
/// única ruta de navegación vía `openPlayer`). [startAt] es la posición
/// guardada de "Continuar" (ui-spec §2.2/§2.6/§2.7) — `Duration.zero` para
/// empezar desde el principio o para directo.
final class PlaybackRequest {
  const PlaybackRequest({required this.channel, this.startAt = Duration.zero, this.queue});

  final Channel channel;
  final Duration startAt;
  final PlaybackQueue? queue;
}
