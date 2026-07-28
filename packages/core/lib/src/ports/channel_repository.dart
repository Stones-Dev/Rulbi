import '../entities/category.dart';
import '../entities/channel.dart';

abstract interface class ChannelRepository {
  /// Reemplaza el contenido derivado de una fuente (canales + categorías)
  /// de forma diferencial: preserva favoritos y watch-state, que se
  /// indexan por `ChannelRef` y no por el `id` de fila (ver ADR-003). La
  /// implementación real (T1.5/`data`) hace el upsert por lotes en
  /// transacción, en un isolate (P1).
  Future<void> replaceSourceContent(String sourceId, Stream<Channel> channels);

  Future<List<Category>> categoriesFor(String sourceId);

  Stream<List<Channel>> watchChannels({required String categoryId});
}
