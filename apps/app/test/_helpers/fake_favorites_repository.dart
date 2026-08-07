import 'dart:async';

import 'package:iptv_core/iptv_core.dart';

/// `FavoritesRepository` en memoria (S5 · Ola 2) — reutilizable entre
/// pantallas que pintan `ChannelRow` (siempre observa `favoriteRefsProvider`
/// para el badge, tenga o no EPG): sin esto, cualquier test que renderice
/// `ChannelRow` sin overridear este provider dispara `iptvDatabaseProvider`
/// de verdad (abre un `IptvDatabase.open()` real durante un widget test).
///
/// `watchAll()` reactivo (`StreamController.broadcast`, no `Stream.value` de
/// un solo disparo) — mismo criterio que `FakeSourceRepository`: el badge
/// de favorito debe actualizarse solo con `upsert`/`toggle`, igual que
/// `DriftFavoritesRepository.watchAll()` con una live query real de drift.
final class FakeFavoritesRepository implements FavoritesRepository {
  final Map<ChannelRef, Favorite> _byChannel = {};
  final _controller = StreamController<List<Favorite>>.broadcast();

  void seed(Favorite favorite) => _byChannel[favorite.channel] = favorite;

  @override
  Future<List<Favorite>> getAll() async => _byChannel.values.toList();

  @override
  Future<Favorite?> find(ChannelRef channel) async => _byChannel[channel];

  @override
  Future<void> upsert(Favorite favorite) async {
    _byChannel[favorite.channel] = favorite;
    _controller.add(_byChannel.values.toList());
  }

  @override
  Stream<List<Favorite>> watchAll() async* {
    yield _byChannel.values.toList();
    yield* _controller.stream;
  }
}
