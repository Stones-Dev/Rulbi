import 'package:flutter/foundation.dart';
import 'package:iptv_core/iptv_core.dart';

/// Ventana con caché de páginas sobre `ChannelRepository.channelsPage`/
/// `countChannels` (S5 · Ola 1, ui-spec §2.3) — la base del listado
/// virtualizado de 100k canales.
///
/// `itemCount` del `ListView.builder` es [totalCount] (el `COUNT(*)` real,
/// ver [init]), con `itemExtent` fijo: la barra de desplazamiento
/// representa los 100k reales y se puede arrastrar al medio, a diferencia
/// de un scroll infinito por lotes que solo conoce lo que ya cargó.
/// [itemAt] devuelve `null` cuando la página que contiene [index] aún no
/// ha llegado — encola su carga y notifica a los listeners cuando
/// termina — para que el `itemBuilder` pinte un esqueleto mientras tanto.
///
/// Contrapartida asumida frente a `ChannelRepository.watchChannels` (que
/// sí es reactivo vía `.watch()` de drift): esta caché no se entera sola
/// de que un import cambió los datos. Quien la usa debe invalidarla
/// (crear una nueva) cuando corresponda — ver `ChannelListScreen`, que la
/// reconstruye al terminar un import o al cambiar las fuentes activas.
class ChannelPageCache extends ChangeNotifier {
  ChannelPageCache({
    required this.repository,
    required this.query,
    this.pageSize = 200,
    this.maxCachedPages = 12,
  });

  final ChannelRepository repository;
  final ChannelQuery query;

  /// Canales por página pedida a `channelsPage`.
  final int pageSize;

  /// Nº máximo de páginas mantenidas en memoria a la vez (LRU) — con el
  /// valor por defecto, como mucho `pageSize * maxCachedPages` canales
  /// viven en Dart de los 100k reales.
  final int maxCachedPages;

  bool _disposed = false;
  bool _isInitialized = false;
  int _totalCount = 0;

  /// Páginas cargadas, en orden de uso más reciente al final — un
  /// literal de `Map` en Dart ya es un `LinkedHashMap` (conserva el orden
  /// de inserción), así que "quitar y reinsertar" en [itemAt] mueve una
  /// página al final sin más estructura ni un import aparte.
  final _pages = <int, List<Channel>>{};
  final _pending = <int>{};

  bool get isInitialized => _isInitialized;
  int get totalCount => _totalCount;

  /// Fija [totalCount] con un `COUNT(*)` real — nunca trae canales.
  Future<void> init() async {
    final count = await repository.countChannels(query);
    if (_disposed) return;
    _totalCount = count;
    _isInitialized = true;
    notifyListeners();
  }

  /// El canal en [index], o `null` si su página todavía no ha llegado
  /// (ya sea porque se acaba de pedir o porque [index] cae en la última
  /// página, parcial). Fuera de `[0, totalCount)` siempre devuelve `null`
  /// sin pedir nada — un `itemBuilder` bien formado nunca debería llegar
  /// aquí, pero no es responsabilidad de la caché confiar en ello.
  Channel? itemAt(int index) {
    if (index < 0 || index >= _totalCount) return null;

    final pageIndex = index ~/ pageSize;
    final page = _pages.remove(pageIndex);
    if (page != null) {
      _pages[pageIndex] = page; // reinserta al final: más reciente
      final withinPage = index % pageSize;
      return withinPage < page.length ? page[withinPage] : null;
    }

    _requestPage(pageIndex);
    return null;
  }

  void _requestPage(int pageIndex) {
    if (_pending.contains(pageIndex)) return;
    _pending.add(pageIndex);

    repository
        .channelsPage(query, offset: pageIndex * pageSize, limit: pageSize)
        .then((channels) {
          _pending.remove(pageIndex);
          if (_disposed) return;
          _pages[pageIndex] = channels;
          _evictLeastRecentlyUsed();
          notifyListeners();
        });
  }

  void _evictLeastRecentlyUsed() {
    while (_pages.length > maxCachedPages) {
      _pages.remove(_pages.keys.first);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
