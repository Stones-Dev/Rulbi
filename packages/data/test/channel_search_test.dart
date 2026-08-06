import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_data/iptv_data.dart';

/// S5 · Ola 1: `DriftChannelRepository.search` con los parámetros nuevos
/// de `ChannelSearchPort` (`type`, `sourceIds`) y con `toFtsMatchQuery` de
/// por medio — `fts_query_test.dart` cubre la sanitización en aislado;
/// aquí se comprueba que llega hasta el motor sin reventar y que el
/// filtrado por tipo/fuente y por tombstone funciona contra FTS5 real.
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
  }) => Channel(
    ref: ChannelRef(sourceId: sourceId, key: refKey),
    sourceId: sourceId,
    type: type,
    name: name,
    url: Uri.parse('http://example.com/$sourceId/$refKey'),
  );

  group('search — entradas que antes lanzaban excepción de SQLite', () {
    setUp(() async {
      await repository.importSourceContent(
        's1',
        Stream.value(channel(sourceId: 's1', refKey: 'a', name: 'Canal España')),
        now: DateTime.utc(2026, 1, 1),
      );
    });

    test('una comilla suelta no lanza y no encuentra nada', () async {
      final result = await repository.search('"');
      expect(result, isEmpty);
    });

    test('un operador FTS5 desnudo (AND) se trata como texto literal', () async {
      // No debe lanzar; "AND" solo no aparece en ningún nombre, así que
      // no hay resultados — lo importante es que no revienta la consulta.
      final result = await repository.search('AND');
      expect(result, isEmpty);
    });

    test('un asterisco suelto no lanza', () async {
      final result = await repository.search('*');
      expect(result, isEmpty);
    });

    test('entrada solo-puntuación devuelve [] sin tocar la BD', () async {
      final result = await repository.search('!!!');
      expect(result, isEmpty);
    });
  });

  group('search — filtrado', () {
    setUp(() async {
      await repository.importSourceContent(
        's1',
        Stream.fromIterable([
          channel(sourceId: 's1', refKey: 'a', name: 'La 1', type: ContentType.live),
          channel(
            sourceId: 's1',
            refKey: 'b',
            name: 'La 1: la película',
            type: ContentType.vod,
          ),
        ]),
        now: DateTime.utc(2026, 1, 1),
      );
      await repository.importSourceContent(
        's2',
        Stream.value(
          channel(sourceId: 's2', refKey: 'a', name: 'La 1 internacional'),
        ),
        now: DateTime.utc(2026, 1, 1),
      );
    });

    test('sin filtro de tipo, encuentra coincidencias de cualquier tipo', () async {
      final result = await repository.search('la 1');
      expect(result.map((c) => c.name).toSet(), {
        'La 1',
        'La 1: la película',
        'La 1 internacional',
      });
    });

    test('filtra por tipo cuando se pide', () async {
      final result = await repository.search('la 1', type: ContentType.vod);
      expect(result.map((c) => c.name), ['La 1: la película']);
    });

    test('filtra por conjunto de fuentes', () async {
      final result = await repository.search('la 1', sourceIds: {'s2'});
      expect(result.map((c) => c.name), ['La 1 internacional']);
    });

    test('sourceIds vacío no toca la BD y devuelve []', () async {
      final result = await repository.search('la 1', sourceIds: {});
      expect(result, isEmpty);
    });

    test('busca por prefijo mientras se escribe', () async {
      final result = await repository.search('esp', sourceIds: {'s1', 's2'});
      // Ninguno de los canales sembrados contiene "esp"; confirma que el
      // prefijo no rompe la consulta y sigue sin encontrar nada.
      expect(result, isEmpty);

      await repository.importSourceContent(
        's1',
        Stream.fromIterable([
          channel(sourceId: 's1', refKey: 'a', name: 'La 1', type: ContentType.live),
          channel(
            sourceId: 's1',
            refKey: 'b',
            name: 'La 1: la película',
            type: ContentType.vod,
          ),
          channel(sourceId: 's1', refKey: 'c', name: 'España TV'),
        ]),
        now: DateTime.utc(2026, 1, 2),
      );

      final afterInsert = await repository.search('esp', sourceIds: {'s1', 's2'});
      expect(afterInsert.map((c) => c.name), ['España TV']);
    });
  });

  group('search — tombstones', () {
    test('un canal tumbado no aparece en resultados', () async {
      await repository.importSourceContent(
        's1',
        Stream.value(channel(sourceId: 's1', refKey: 'a', name: 'Canal España')),
        now: DateTime.utc(2026, 1, 1),
      );
      await repository.importSourceContent(
        's1',
        const Stream.empty(),
        now: DateTime.utc(2026, 1, 2),
      );

      final result = await repository.search('espana', sourceIds: {'s1'});

      expect(result, isEmpty);
    });
  });
}
