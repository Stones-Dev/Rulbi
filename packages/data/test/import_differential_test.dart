import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_data/iptv_data.dart';

import 'package:iptv_data/testing.dart' as v1;

/// T1.6b: batería del upsert diferencial de `DriftChannelRepository
/// .importSourceContent` contra SQLite real (`NativeDatabase.memory()` —
/// mide semántica, no jank; el único test que mide tiempos es
/// `import_100k_benchmark_test.dart`, con el patrón correcto documentado
/// ahí, ver hallazgo de T1.5b).
void main() {
  // Varios tests de este archivo abren deliberadamente más de un
  // IptvDatabase en el mismo proceso (convergencia con `dbInverse`, el
  // `db` sin usar del setUp() compartido junto al `migratedDb` de la
  // migración) — cada uno sobre su propio executor en memoria/archivo
  // independiente, no el mismo compartido, así que la advertencia de
  // drift sobre condiciones de carrera no aplica aquí.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late IptvDatabase db;
  late DriftChannelRepository repository;
  late DriftFavoritesRepository favorites;

  setUp(() {
    db = IptvDatabase(NativeDatabase.memory());
    repository = DriftChannelRepository(db);
    favorites = DriftFavoritesRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Channel channel({
    required String sourceId,
    required String refKey,
    String name = 'Canal',
    String url = 'http://example.com/stream',
    String? categoryId,
    String? tvgId,
    Map<String, String> metadata = const {},
  }) => Channel(
    ref: ChannelRef(sourceId: sourceId, key: refKey),
    sourceId: sourceId,
    categoryId: categoryId,
    type: ContentType.live,
    name: name,
    url: Uri.parse(url),
    tvgId: tvgId,
    metadata: metadata,
  );

  Future<List<ChannelRow>> rawRowsFor(String sourceId) => (db.select(
    db.channels,
  )..where((c) => c.sourceId.equals(sourceId))).get();

  group('aparición', () {
    test('inserta canales nuevos y search los encuentra', () async {
      final stats = await repository.importSourceContent(
        's1',
        Stream.fromIterable([
          channel(sourceId: 's1', refKey: 'a', name: 'Canal A'),
          channel(sourceId: 's1', refKey: 'b', name: 'Canal B'),
          channel(sourceId: 's1', refKey: 'c', name: 'Canal C'),
        ]),
        now: DateTime(2026, 1, 1),
      );

      expect(
        stats,
        const SourceImportStats(
          inserted: 3,
          updated: 0,
          unchanged: 0,
          tombstoned: 0,
          resurrected: 0,
          duplicateRefs: 0,
        ),
      );
      final results = await repository.search('canal');
      expect(results.map((c) => c.ref.key).toSet(), {'a', 'b', 'c'});
    });
  });

  group('idempotencia', () {
    test(
      'importar el mismo contenido dos veces no genera writes de más',
      () async {
        Stream<Channel> source() => Stream.fromIterable([
          channel(sourceId: 's1', refKey: 'a', name: 'Canal A'),
          channel(sourceId: 's1', refKey: 'b', name: 'Canal B'),
        ]);

        await repository.importSourceContent(
          's1',
          source(),
          now: DateTime(2026, 1, 1),
        );
        final before = await rawRowsFor('s1');

        final secondStats = await repository.importSourceContent(
          's1',
          source(),
          now: DateTime(2026, 1, 2),
        );
        final after = await rawRowsFor('s1');

        expect(
          secondStats,
          const SourceImportStats(
            inserted: 0,
            updated: 0,
            unchanged: 2,
            tombstoned: 0,
            resurrected: 0,
            duplicateRefs: 0,
          ),
        );
        // Cero writes de más: mismos ids, mismo contenido — si hubiera
        // habido un DELETE+insert, el autoincremental habría avanzado.
        expect(
          after.map((r) => r.id).toSet(),
          before.map((r) => r.id).toSet(),
        );
        expect(after, before);
      },
    );
  });

  group('desaparición', () {
    test(
      'un canal ausente en el segundo import se tumba, no se borra',
      () async {
        await repository.importSourceContent(
          's1',
          Stream.fromIterable([
            channel(sourceId: 's1', refKey: 'a', categoryId: 'catA'),
            channel(sourceId: 's1', refKey: 'b', categoryId: 'catA'),
          ]),
          now: DateTime(2026, 1, 1),
        );

        final stats = await repository.importSourceContent(
          's1',
          Stream.fromIterable([
            channel(sourceId: 's1', refKey: 'b', categoryId: 'catA'),
          ]),
          now: DateTime(2026, 1, 2),
        );

        expect(
          stats,
          const SourceImportStats(
            inserted: 0,
            updated: 0,
            unchanged: 1,
            tombstoned: 1,
            resurrected: 0,
            duplicateRefs: 0,
          ),
        );

        final rows = await rawRowsFor('s1');
        final tombstoned = rows.singleWhere((r) => r.refKey == 'a');
        expect(tombstoned.deletedAt, DateTime(2026, 1, 2));

        final results = await repository.search('canal');
        expect(results.map((c) => c.ref.key), ['b']);

        final visible = await repository
            .watchChannels(categoryId: 'catA')
            .first;
        expect(visible.map((c) => c.ref.key), ['b']);
      },
    );
  });

  group('reaparición', () {
    test(
      'un canal que reaparece se resucita conservando el id de fila',
      () async {
        await repository.importSourceContent(
          's1',
          Stream.fromIterable([channel(sourceId: 's1', refKey: 'a')]),
          now: DateTime(2026, 1, 1),
        );
        final idBeforeTombstone = (await rawRowsFor('s1')).single.id;

        await repository.importSourceContent(
          's1',
          const Stream<Channel>.empty(),
          now: DateTime(2026, 1, 2),
        );
        expect(
          (await rawRowsFor('s1')).single.deletedAt,
          DateTime(2026, 1, 2),
        );

        final stats = await repository.importSourceContent(
          's1',
          Stream.fromIterable([channel(sourceId: 's1', refKey: 'a')]),
          now: DateTime(2026, 1, 3),
        );

        expect(
          stats,
          const SourceImportStats(
            inserted: 0,
            updated: 0,
            unchanged: 0,
            tombstoned: 0,
            resurrected: 1,
            duplicateRefs: 0,
          ),
        );
        final row = (await rawRowsFor('s1')).single;
        expect(row.deletedAt, isNull);
        expect(row.id, idBeforeTombstone);
      },
    );
  });

  group('cambio', () {
    test(
      'mismo refKey con name/url distintos se actualiza y FTS5 refleja el '
      'nombre nuevo',
      () async {
        await repository.importSourceContent(
          's1',
          Stream.fromIterable([
            channel(
              sourceId: 's1',
              refKey: 'a',
              name: 'Canal Viejo',
              url: 'http://example.com/old',
            ),
          ]),
          now: DateTime(2026, 1, 1),
        );

        final stats = await repository.importSourceContent(
          's1',
          Stream.fromIterable([
            channel(
              sourceId: 's1',
              refKey: 'a',
              name: 'Canal Nuevo',
              url: 'http://example.com/new',
            ),
          ]),
          now: DateTime(2026, 1, 2),
        );

        expect(
          stats,
          const SourceImportStats(
            inserted: 0,
            updated: 1,
            unchanged: 0,
            tombstoned: 0,
            resurrected: 0,
            duplicateRefs: 0,
          ),
        );
        expect(
          (await repository.search('nuevo')).map((c) => c.ref.key),
          ['a'],
        );
        expect(await repository.search('viejo'), isEmpty);
      },
    );

    test('un cambio solo en metadata también cuenta como updated', () async {
      await repository.importSourceContent(
        's1',
        Stream.fromIterable([
          channel(
            sourceId: 's1',
            refKey: 'a',
            metadata: const {'group-title': 'General'},
          ),
        ]),
        now: DateTime(2026, 1, 1),
      );

      final stats = await repository.importSourceContent(
        's1',
        Stream.fromIterable([
          channel(
            sourceId: 's1',
            refKey: 'a',
            metadata: const {'group-title': 'Deportes'},
          ),
        ]),
        now: DateTime(2026, 1, 2),
      );

      expect(stats.updated, 1);
      expect(stats.unchanged, 0);
    });
  });

  group('supervivencia de favoritos/watch-state (ADR-003)', () {
    test(
      'un favorito sobrevive a aparición -> cambio -> desaparición -> '
      'reaparición del mismo canal',
      () async {
        const ref = ChannelRef(sourceId: 's1', key: 'a');

        await repository.importSourceContent(
          's1',
          Stream.fromIterable([channel(sourceId: 's1', refKey: 'a')]),
          now: DateTime(2026, 1, 1),
        );
        await favorites.upsert(
          Favorite(channel: ref, updatedAt: DateTime(2026, 1, 1)),
        );

        // cambio
        await repository.importSourceContent(
          's1',
          Stream.fromIterable([
            channel(sourceId: 's1', refKey: 'a', name: 'Renombrado'),
          ]),
          now: DateTime(2026, 1, 2),
        );
        expect((await favorites.find(ref))!.isDeleted, isFalse);

        // desaparición
        await repository.importSourceContent(
          's1',
          const Stream<Channel>.empty(),
          now: DateTime(2026, 1, 3),
        );
        expect((await favorites.find(ref))!.isDeleted, isFalse);

        // reaparición
        await repository.importSourceContent(
          's1',
          Stream.fromIterable([channel(sourceId: 's1', refKey: 'a')]),
          now: DateTime(2026, 1, 4),
        );
        final survivor = await favorites.find(ref);
        expect(survivor, isNotNull);
        expect(survivor!.isDeleted, isFalse);
      },
    );
  });

  group('colisión de ChannelRef entre fuentes distintas', () {
    test(
      'el mismo refKey bajo dos sourceId produce filas independientes',
      () async {
        await repository.importSourceContent(
          's1',
          Stream.fromIterable([channel(sourceId: 's1', refKey: 'a')]),
          now: DateTime(2026, 1, 1),
        );
        await repository.importSourceContent(
          's2',
          Stream.fromIterable([channel(sourceId: 's2', refKey: 'a')]),
          now: DateTime(2026, 1, 1),
        );

        await favorites.upsert(
          Favorite(
            channel: const ChannelRef(sourceId: 's1', key: 'a'),
            updatedAt: DateTime(2026, 1, 1),
          ),
        );

        // tumbar el de s1 no debe afectar al de s2.
        await repository.importSourceContent(
          's1',
          const Stream<Channel>.empty(),
          now: DateTime(2026, 1, 2),
        );

        final s1Row = (await rawRowsFor('s1')).single;
        final s2Row = (await rawRowsFor('s2')).single;
        expect(s1Row.deletedAt, isNotNull);
        expect(s2Row.deletedAt, isNull);

        // el favorito de s1 no es visible como favorito de s2.
        expect(
          await favorites.find(const ChannelRef(sourceId: 's2', key: 'a')),
          isNull,
        );
      },
    );
  });

  group('duplicado intra-import', () {
    test(
      'dos canales con el mismo refKey en el mismo stream: gana el último',
      () async {
        final stats = await repository.importSourceContent(
          's1',
          Stream.fromIterable([
            channel(sourceId: 's1', refKey: 'a', name: 'Primero'),
            channel(sourceId: 's1', refKey: 'a', name: 'Segundo'),
          ]),
          now: DateTime(2026, 1, 1),
        );

        expect(
          stats,
          const SourceImportStats(
            inserted: 1,
            updated: 0,
            unchanged: 0,
            tombstoned: 0,
            resurrected: 0,
            duplicateRefs: 1,
          ),
        );
        final rows = await rawRowsFor('s1');
        expect(rows, hasLength(1));
        expect(rows.single.name, 'Segundo');
      },
    );
  });

  group('convergencia', () {
    // Nota de diseño verificada aquí (no solo documentada): cada llamada a
    // `importSourceContent` trata su stream como la verdad COMPLETA
    // vigente de la fuente en ese instante, no un parche incremental
    // sobre la llamada anterior — es lo que hace posible detectar
    // desapariciones. Así que "convergencia" no es "llamar dos veces con
    // mitades distintas converge" (eso tumbaría la mitad ausente en la
    // segunda llamada, correctamente) — es que el ORDEN en que los
    // canales llegan dentro de un mismo stream no debe afectar al estado
    // final, más allá del propio criterio de "gana el último" ante un
    // duplicado (ya cubierto en el grupo de arriba).
    test(
      'el orden de los canales dentro de un mismo import no cambia el '
      'estado final',
      () async {
        Channel a() => channel(sourceId: 's1', refKey: 'a', name: 'A');
        Channel b() => channel(sourceId: 's1', refKey: 'b', name: 'B');

        await repository.importSourceContent(
          's1',
          Stream.fromIterable([a(), b()]),
          now: DateTime(2026, 1, 1),
        );

        final dbInverse = IptvDatabase(NativeDatabase.memory());
        addTearDown(dbInverse.close);
        final repoInverse = DriftChannelRepository(dbInverse);
        await repoInverse.importSourceContent(
          's1',
          Stream.fromIterable([b(), a()]),
          now: DateTime(2026, 1, 1),
        );

        Future<Set<(String, String?)>> liveFingerprint(
          IptvDatabase database,
        ) async {
          final rows = await (database.select(
            database.channels,
          )..where((c) => c.deletedAt.isNull())).get();
          return rows.map((r) => (r.refKey, r.contentHash)).toSet();
        }

        final fingerprint = await liveFingerprint(db);
        expect(fingerprint, hasLength(2));
        expect(fingerprint, await liveFingerprint(dbInverse));
      },
    );
  });

  group('countBySource (Gestión de fuentes, S4 · Ola 3, ui-spec §2.10)', () {
    test('fuente sin canales devuelve 0', () async {
      expect(await repository.countBySource('inexistente'), 0);
    });

    test('cuenta solo los canales vivos tras un import', () async {
      await repository.importSourceContent(
        's1',
        Stream.fromIterable([
          channel(sourceId: 's1', refKey: 'a'),
          channel(sourceId: 's1', refKey: 'b'),
          channel(sourceId: 's1', refKey: 'c'),
        ]),
        now: DateTime(2026, 1, 1),
      );

      expect(await repository.countBySource('s1'), 3);
    });

    test(
      'un segundo import que tumba la mitad de los canales reduce el '
      'recuento (los tombstones no cuentan)',
      () async {
        await repository.importSourceContent(
          's1',
          Stream.fromIterable([
            channel(sourceId: 's1', refKey: 'a'),
            channel(sourceId: 's1', refKey: 'b'),
            channel(sourceId: 's1', refKey: 'c'),
            channel(sourceId: 's1', refKey: 'd'),
          ]),
          now: DateTime(2026, 1, 1),
        );

        // Solo 'a' y 'b' reaparecen -> 'c' y 'd' se tumban.
        await repository.importSourceContent(
          's1',
          Stream.fromIterable([
            channel(sourceId: 's1', refKey: 'a'),
            channel(sourceId: 's1', refKey: 'b'),
          ]),
          now: DateTime(2026, 1, 2),
        );

        expect(await repository.countBySource('s1'), 2);
      },
    );

    test('no mezcla canales de otra fuente', () async {
      await repository.importSourceContent(
        's1',
        Stream.fromIterable([channel(sourceId: 's1', refKey: 'a')]),
        now: DateTime(2026, 1, 1),
      );
      await repository.importSourceContent(
        's2',
        Stream.fromIterable([
          channel(sourceId: 's2', refKey: 'x'),
          channel(sourceId: 's2', refKey: 'y'),
        ]),
        now: DateTime(2026, 1, 1),
      );

      expect(await repository.countBySource('s1'), 1);
      expect(await repository.countBySource('s2'), 2);
    });
  });

  group('migración v1 -> v4', () {
    test(
      'una BD creada con el esquema v1 abre en la versión actual sin '
      'perder filas de channels, con las columnas nuevas en NULL',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'iptv_migration_test_',
        );
        addTearDown(() async {
          if (tempDir.existsSync()) await tempDir.delete(recursive: true);
        });
        final file = File('${tempDir.path}/migration.sqlite');

        // 1. Materializa el esquema v1 REAL (generado por `drift_dev
        // schema generate` a partir del snapshot volcado antes de tocar
        // `channels.dart`, ver `drift_schemas/drift_schema_v1.json`) y
        // deja una fila de datos reales, como si fuera una instalación
        // existente en producción. El helper generado (`schema_v1.dart`)
        // no trae companions/data classes (se generó sin
        // `--companions`/`--data-classes`, y no hacen falta solo para
        // verificar la migración), así que la fila se inserta con SQL
        // crudo, no con la API tipada.
        final v1Db = v1.DatabaseAtV1(NativeDatabase(file));
        await v1Db.customStatement(
          'INSERT INTO channels (source_id, ref_key, content_type, name, url) '
          'VALUES (?, ?, ?, ?, ?)',
          [
            's1',
            'a',
            'live',
            'Canal preexistente',
            'http://example.com/pre-existente',
          ],
        );
        await v1Db.close();

        // 2. Reabre el MISMO archivo con el esquema real (v2, el que
        // vive en el árbol) — debe migrar sola vía onUpgrade.
        final migratedDb = IptvDatabase(NativeDatabase(file));
        addTearDown(migratedDb.close);

        final rows = await migratedDb.select(migratedDb.channels).get();
        expect(rows, hasLength(1));
        expect(rows.single.name, 'Canal preexistente');
        expect(rows.single.sourceId, 's1');
        // Filas de antes de la migración: sin hash previo real, no hay
        // forma honesta de decir que "no cambiaron" — quedan NULL hasta
        // el próximo refresco real (ver docstring de
        // `Channels.contentHash`).
        expect(rows.single.deletedAt, isNull);
        expect(rows.single.contentHash, isNull);
        expect(migratedDb.schemaVersion, 4);
      },
    );
  });
}
