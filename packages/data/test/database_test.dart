import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_data/iptv_data.dart';

void main() {
  late IptvDatabase db;

  setUp(() {
    db = IptvDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('el esquema abre en schemaVersion 3', () async {
    // Fuerza la apertura real (createAll) leyendo algo de la BD.
    await db.select(db.sources).get();
    expect(db.schemaVersion, 3);
  });

  group('tombstones (ADR-003)', () {
    // Sin sub-segundo: por defecto drift guarda DateTime como epoch en
    // segundos (storeDateTimeAsText no está activado), así que un
    // DateTime.now() con milisegundos no haría round-trip exacto — no
    // es un bug del esquema, es la precisión de almacenamiento.
    test('favorites persiste updatedAt y deletedAt', () async {
      final now = DateTime(2026, 1, 1, 12, 30);
      await db
          .into(db.favorites)
          .insert(
            FavoritesCompanion.insert(
              sourceId: 's1',
              refKey: 'canal-1',
              updatedAt: Value(now),
            ),
          );

      final row = await (db.select(
        db.favorites,
      )..where((f) => f.refKey.equals('canal-1'))).getSingle();

      expect(row.deletedAt, isNull);
      expect(row.updatedAt, now);
    });

    test('un tombstone se persiste con deletedAt no nulo', () async {
      final now = DateTime(2026, 1, 1, 12, 30);
      await db
          .into(db.favorites)
          .insert(
            FavoritesCompanion.insert(
              sourceId: 's1',
              refKey: 'canal-1',
              updatedAt: Value(now),
              deletedAt: Value(now),
            ),
          );

      final row = await (db.select(
        db.favorites,
      )..where((f) => f.refKey.equals('canal-1'))).getSingle();

      expect(row.deletedAt, now);
    });
  });

  group('FTS5 con normalización de acentos', () {
    setUp(() async {
      await db
          .into(db.channels)
          .insert(
            ChannelsCompanion.insert(
              sourceId: 's1',
              refKey: 'espana-tv',
              contentType: 'live',
              name: 'España TV',
              url: 'http://example.com/stream',
            ),
          );
      await db
          .into(db.channels)
          .insert(
            ChannelsCompanion.insert(
              sourceId: 's1',
              refKey: 'otro',
              contentType: 'live',
              name: 'Otro canal',
              url: 'http://example.com/other',
            ),
          );
    });

    Future<List<String>> searchNames(String query) async {
      final rows = await db
          .customSelect(
            'SELECT c.name AS name FROM channels_fts f '
            'JOIN channels c ON c.id = f.rowid '
            'WHERE channels_fts MATCH ?',
            variables: [Variable<String>(query)],
          )
          .get();
      return rows.map((r) => r.read<String>('name')).toList();
    }

    test('"espana" (sin acento) encuentra "España"', () async {
      expect(await searchNames('espana'), ['España TV']);
    });

    test('"ESPAÑA" (mayúsculas con acento) también encuentra', () async {
      expect(await searchNames('ESPAÑA'), ['España TV']);
    });

    test(
      '"Espana" (mayúscula inicial, sin acento) también encuentra',
      () async {
        expect(await searchNames('Espana'), ['España TV']);
      },
    );

    test('una consulta sin coincidencias no devuelve nada', () async {
      expect(await searchNames('inexistente'), isEmpty);
    });

    test(
      'el índice se actualiza al renombrar un canal (trigger AFTER UPDATE)',
      () async {
        await (db.update(db.channels)..where((c) => c.refKey.equals('otro')))
            .write(const ChannelsCompanion(name: Value('Alemania TV')));

        expect(await searchNames('alemania'), ['Alemania TV']);
        expect(await searchNames('otro'), isEmpty);
      },
    );

    test(
      'el índice se actualiza al borrar un canal (trigger AFTER DELETE)',
      () async {
        await (db.delete(
          db.channels,
        )..where((c) => c.refKey.equals('espana-tv'))).go();

        expect(await searchNames('espana'), isEmpty);
      },
    );
  });
}
