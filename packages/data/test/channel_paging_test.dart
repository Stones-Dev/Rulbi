import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_data/iptv_data.dart';

/// S5 · Ola 1: listado virtualizado de canales (ui-spec §2.3) sobre
/// `ChannelRepository.countChannels`/`channelsPage`/`categoriesWithCount`/
/// `findByRefs` — la base de `ChannelPageCache` (`apps/app`). Contra
/// SQLite real (`NativeDatabase.memory()`), no un fake: lo que importa
/// aquí es el SQL generado (orden estable, filtros, `LIMIT`/`OFFSET`), no
/// la orquestación de `core`.
void main() {
  late IptvDatabase db;
  late DriftChannelRepository repository;

  setUp(() {
    db = IptvDatabase(NativeDatabase.memory());
    repository = DriftChannelRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Channel channel({
    required String sourceId,
    required String refKey,
    required String name,
    ContentType type = ContentType.live,
    String? categoryId,
  }) => Channel(
    ref: ChannelRef(sourceId: sourceId, key: refKey),
    sourceId: sourceId,
    categoryId: categoryId,
    type: type,
    name: name,
    url: Uri.parse('http://example.com/$sourceId/$refKey'),
  );

  Future<void> seed(List<Channel> channels) => repository.importSourceContent(
    channels.isEmpty ? 's1' : channels.first.sourceId,
    Stream.fromIterable(channels),
    now: DateTime.utc(2026, 1, 1),
  );

  group('countChannels', () {
    test('cuenta solo los canales vivos del tipo/fuente pedidos', () async {
      await seed([
        channel(sourceId: 's1', refKey: 'a', name: 'A', type: ContentType.live),
        channel(sourceId: 's1', refKey: 'b', name: 'B', type: ContentType.live),
        channel(sourceId: 's1', refKey: 'c', name: 'C', type: ContentType.vod),
      ]);

      final count = await repository.countChannels(
        const ChannelQuery(type: ContentType.live, sourceIds: {'s1'}),
      );

      expect(count, 2);
    });

    test('un conjunto de fuentes vacío cuenta 0 (fuente desactivada/oculta)', () async {
      await seed([
        channel(sourceId: 's1', refKey: 'a', name: 'A'),
      ]);

      final count = await repository.countChannels(
        const ChannelQuery(type: ContentType.live, sourceIds: {}),
      );

      expect(count, 0);
    });

    test('excluye tombstones', () async {
      await seed([channel(sourceId: 's1', refKey: 'a', name: 'A')]);
      // Segundo import sin el canal: se tumba, no se borra.
      await seed([]);

      final count = await repository.countChannels(
        const ChannelQuery(type: ContentType.live, sourceIds: {'s1'}),
      );

      expect(count, 0);
    });

    test('respeta la categoría cuando se pide', () async {
      await seed([
        channel(sourceId: 's1', refKey: 'a', name: 'A', categoryId: 'cat-1'),
        channel(sourceId: 's1', refKey: 'b', name: 'B', categoryId: 'cat-2'),
      ]);

      final count = await repository.countChannels(
        const ChannelQuery(
          type: ContentType.live,
          sourceIds: {'s1'},
          categoryId: 'cat-1',
        ),
      );

      expect(count, 1);
    });
  });

  group('channelsPage', () {
    test('ordena por nombre y desempata por id de forma estable', () async {
      await seed([
        channel(sourceId: 's1', refKey: 'z', name: 'Zeta'),
        channel(sourceId: 's1', refKey: 'a1', name: 'Alfa'),
        channel(sourceId: 's1', refKey: 'a2', name: 'Alfa'), // nombre duplicado
        channel(sourceId: 's1', refKey: 'm', name: 'Medio'),
      ]);

      final page = await repository.channelsPage(
        const ChannelQuery(type: ContentType.live, sourceIds: {'s1'}),
        offset: 0,
        limit: 10,
      );

      expect(page.map((c) => c.ref.key), ['a1', 'a2', 'm', 'z']);
    });

    test('offset/limit paginan sin saltarse ni repetir filas', () async {
      final channels = [
        for (var i = 0; i < 10; i++)
          channel(
            sourceId: 's1',
            refKey: 'c$i',
            // Padding para que el orden alfabético coincida con el numérico.
            name: 'Canal ${i.toString().padLeft(2, '0')}',
          ),
      ];
      await seed(channels);

      final firstPage = await repository.channelsPage(
        const ChannelQuery(type: ContentType.live, sourceIds: {'s1'}),
        offset: 0,
        limit: 4,
      );
      final secondPage = await repository.channelsPage(
        const ChannelQuery(type: ContentType.live, sourceIds: {'s1'}),
        offset: 4,
        limit: 4,
      );

      expect(firstPage.map((c) => c.ref.key), ['c0', 'c1', 'c2', 'c3']);
      expect(secondPage.map((c) => c.ref.key), ['c4', 'c5', 'c6', 'c7']);
    });

    test('excluye tombstones y otras fuentes/tipos', () async {
      await seed([
        channel(sourceId: 's1', refKey: 'a', name: 'A', type: ContentType.live),
        channel(sourceId: 's1', refKey: 'b', name: 'B', type: ContentType.vod),
        channel(sourceId: 's2', refKey: 'c', name: 'C', type: ContentType.live),
      ]);
      await repository.importSourceContent(
        's1',
        const Stream.empty(),
        now: DateTime.utc(2026, 1, 2),
      ); // tumba 'a'

      final page = await repository.channelsPage(
        const ChannelQuery(type: ContentType.live, sourceIds: {'s1', 's2'}),
        offset: 0,
        limit: 10,
      );

      expect(page.map((c) => c.ref.key), ['c']);
    });
  });

  group('categoriesWithCount', () {
    test('cada categoría trae su nº de canales vivos', () async {
      await seed([
        channel(sourceId: 's1', refKey: 'a', name: 'A', categoryId: 'deportes'),
        channel(sourceId: 's1', refKey: 'b', name: 'B', categoryId: 'deportes'),
        channel(sourceId: 's1', refKey: 'c', name: 'C', categoryId: 'noticias'),
      ]);
      await db
          .into(db.categories)
          .insert(
            CategoriesCompanion.insert(
              id: 'deportes',
              sourceId: 's1',
              contentType: 'live',
              name: 'Deportes',
            ),
          );
      await db
          .into(db.categories)
          .insert(
            CategoriesCompanion.insert(
              id: 'noticias',
              sourceId: 's1',
              contentType: 'live',
              name: 'Noticias',
            ),
          );

      final result = await repository.categoriesWithCount(
        const ChannelQuery(type: ContentType.live, sourceIds: {'s1'}),
      );

      final byId = {for (final c in result) c.category.id: c.channelCount};
      expect(byId['deportes'], 2);
      expect(byId['noticias'], 1);
    });

    test('una categoría sin canales vivos aparece con contador 0', () async {
      await db
          .into(db.categories)
          .insert(
            CategoriesCompanion.insert(
              id: 'vacia',
              sourceId: 's1',
              contentType: 'live',
              name: 'Vacía',
            ),
          );

      final result = await repository.categoriesWithCount(
        const ChannelQuery(type: ContentType.live, sourceIds: {'s1'}),
      );

      expect(result, hasLength(1));
      expect(result.single.channelCount, 0);
    });
  });

  group('findByRefs', () {
    test('hidrata varios refs a la vez, preservando solo los vivos', () async {
      // Dos imports separados, uno por fuente: `importSourceContent`
      // asume que todo el stream pertenece a la misma fuente que su
      // parámetro `sourceId` (deduplica por `refKey` a secas, no por
      // `(sourceId, refKey)`) — mezclar fuentes en un único stream
      // rompería esa precondición, no es lo que este test quiere probar.
      await seed([
        channel(sourceId: 's1', refKey: 'a', name: 'A'),
        channel(sourceId: 's1', refKey: 'b', name: 'B'),
      ]);
      await repository.importSourceContent(
        's2',
        Stream.value(channel(sourceId: 's2', refKey: 'a', name: 'A de s2')),
        now: DateTime.utc(2026, 1, 1),
      );

      final result = await repository.findByRefs([
        const ChannelRef(sourceId: 's1', key: 'a'),
        const ChannelRef(sourceId: 's2', key: 'a'),
        const ChannelRef(sourceId: 's1', key: 'no-existe'),
      ]);

      expect(result.map((c) => c.name).toSet(), {'A', 'A de s2'});
    });

    test('una lista vacía de refs no toca la base de datos y devuelve []', () async {
      final result = await repository.findByRefs(const []);
      expect(result, isEmpty);
    });

    test('un ref tumbado no se hidrata', () async {
      await seed([channel(sourceId: 's1', refKey: 'a', name: 'A')]);
      await repository.importSourceContent(
        's1',
        const Stream.empty(),
        now: DateTime.utc(2026, 1, 2),
      );

      final result = await repository.findByRefs([
        const ChannelRef(sourceId: 's1', key: 'a'),
      ]);

      expect(result, isEmpty);
    });
  });
}
