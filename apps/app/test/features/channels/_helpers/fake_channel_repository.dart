import 'package:iptv_core/iptv_core.dart';

/// Fake de `ChannelRepository` para los tests de la sección de canales
/// (S5 · Ola 1) — mismo criterio que `_helpers/fakes.dart` de
/// `features/sources`: en memoria, sin drift, registra cómo se le llamó
/// cuando el test lo necesita.
final class FakeChannelListRepository implements ChannelRepository {
  FakeChannelListRepository({List<Channel> channels = const []})
    : _channels = List.of(channels);

  final List<Channel> _channels;

  /// Offsets pedidos a [channelsPage], en orden — para verificar que
  /// `ChannelPageCache` no repite peticiones de la misma página.
  final List<int> pageRequests = [];

  /// Si no es null, cada [channelsPage] espera a que se complete antes de
  /// devolver — para probar que dos peticiones concurrentes de la misma
  /// página se deduplican de verdad (no solo "no truenan").
  Future<void>? pageDelay;

  @override
  Future<int> countChannels(ChannelQuery query) async => _matching(query).length;

  @override
  Future<List<Channel>> channelsPage(
    ChannelQuery query, {
    required int offset,
    required int limit,
  }) async {
    pageRequests.add(offset);
    if (pageDelay != null) await pageDelay;
    final matching = _matching(query);
    if (offset >= matching.length) return const [];
    final end = (offset + limit).clamp(0, matching.length);
    return matching.sublist(offset, end);
  }

  List<Channel> _matching(ChannelQuery query) => _channels
      .where(
        (c) =>
            c.type == query.type &&
            query.sourceIds.contains(c.sourceId) &&
            (query.categoryId == null || c.categoryId == query.categoryId),
      )
      .toList();

  /// Cuenta agrupando por `categoryId` entre los canales sembrados —
  /// suficiente para verificar el cableado del panel de categorías en un
  /// widget test; la lógica SQL real (`LEFT JOIN` + `GROUP BY`) ya está
  /// cubierta contra SQLite de verdad en `channel_paging_test.dart`
  /// (`packages/data`), no hace falta reimplementarla aquí.
  @override
  Future<List<CategoryWithCount>> categoriesWithCount(
    ChannelQuery query,
  ) async {
    final counts = <String, int>{};
    for (final channel in _matching(query)) {
      final categoryId = channel.categoryId;
      if (categoryId == null) continue;
      counts[categoryId] = (counts[categoryId] ?? 0) + 1;
    }
    return [
      for (final entry in counts.entries)
        CategoryWithCount(
          category: Category(
            id: entry.key,
            sourceId: query.sourceIds.isEmpty ? '' : query.sourceIds.first,
            type: query.type,
            name: entry.key,
          ),
          channelCount: entry.value,
        ),
    ];
  }

  @override
  Future<List<Channel>> findByRefs(List<ChannelRef> refs) async {
    final byRef = {for (final channel in _channels) channel.ref: channel};
    return [for (final ref in refs) ?byRef[ref]];
  }

  @override
  Future<SourceImportStats> importSourceContent(
    String sourceId,
    Stream<Channel> channels, {
    required DateTime now,
  }) => throw UnimplementedError();

  @override
  Future<List<Category>> categoriesFor(String sourceId) async => const [];

  @override
  Stream<List<Channel>> watchChannels({required String categoryId}) =>
      const Stream.empty();

  @override
  Future<int> countBySource(String sourceId) async => 0;

  @override
  Future<int> purgeOrphanTombstones({required DateTime deletedBefore}) async =>
      0;
}
