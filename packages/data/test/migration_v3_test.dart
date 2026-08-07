import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_data/iptv_data.dart';
import 'package:iptv_data/testing.dart' as v1;

/// Migración v2 -> v3 (S5 · Ola 1): índices de listado paginado sobre
/// `channels` (`idx_channels_type_name`, `idx_channels_category_name`).
/// No basta con comprobar que el DDL existe (`PRAGMA index_list`) — el
/// motivo de la migración es que el listado de 100k canales deje de ser
/// un scan+sort completo, así que también se verifica con `EXPLAIN QUERY
/// PLAN` que la consulta real de `channelsPage`/`countChannels`
/// (`ChannelRepository`, ver `channel_repository.dart`) efectivamente usa
/// el índice, no solo que este exista sin usarse.
void main() {
  Future<Set<String>> indexNamesOf(IptvDatabase db, String table) async {
    final rows = await db.customSelect('PRAGMA index_list($table)').get();
    return rows.map((r) => r.data['name'] as String).toSet();
  }

  group('migración v2 -> v3: índices de listado', () {
    test('una BD creada de cero (onCreate) trae ambos índices', () async {
      final db = IptvDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      // Fuerza la apertura real (createAll).
      await db.select(db.sources).get();

      final indexNames = await indexNamesOf(db, 'channels');
      expect(indexNames, contains('idx_channels_type_name'));
      expect(indexNames, contains('idx_channels_category_name'));
    });

    test(
      'una BD migrada desde v1 (onUpgrade) también trae ambos índices',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'iptv_migration_v3_test_',
        );
        addTearDown(() async {
          if (tempDir.existsSync()) await tempDir.delete(recursive: true);
        });
        final file = File('${tempDir.path}/migration.sqlite');

        // Mismo patrón que `import_differential_test.dart`: materializa
        // el esquema v1 real, luego reabre con el esquema actual y deja
        // que `onUpgrade` haga su trabajo.
        final v1Db = v1.DatabaseAtV1(NativeDatabase(file));
        await v1Db.close();

        final migratedDb = IptvDatabase(NativeDatabase(file));
        addTearDown(migratedDb.close);
        await migratedDb.select(migratedDb.sources).get();

        final indexNames = await indexNamesOf(migratedDb, 'channels');
        expect(indexNames, contains('idx_channels_type_name'));
        expect(indexNames, contains('idx_channels_category_name'));
        // La migración real desde v1 hoy pasa por v2, v3 y v4 (ADR-008,
        // S5 · Ola 2) — este test solo verifica que la parada v3 sigue
        // trayendo los índices en el camino, no el esquema final.
        expect(migratedDb.schemaVersion, 4);
      },
    );

    test(
      'la consulta de listado paginado usa idx_channels_type_name, no un scan',
      () async {
        final db = IptvDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        await db.select(db.sources).get();

        final plan = await db
            .customSelect(
              'EXPLAIN QUERY PLAN '
              'SELECT * FROM channels '
              'WHERE content_type = ? AND deleted_at IS NULL '
              'ORDER BY name, id LIMIT 200 OFFSET 400',
              variables: const [Variable<String>('live')],
            )
            .get();

        final detail = plan.map((r) => r.data['detail'] as String).join(' | ');
        expect(
          detail,
          contains('idx_channels_type_name'),
          reason:
              'sin el índice, esta consulta sería un SCAN completo de la '
              'tabla channels en cada página — inviable sobre 100k filas '
              '(RNF-01). Plan real: $detail',
        );
      },
    );

    test(
      'el panel de categorías usa idx_channels_category_name para el conteo',
      () async {
        final db = IptvDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        await db.select(db.sources).get();

        final plan = await db
            .customSelect(
              'EXPLAIN QUERY PLAN '
              'SELECT category_id, COUNT(*) FROM channels '
              'WHERE category_id = ? AND deleted_at IS NULL '
              'GROUP BY category_id',
              variables: const [Variable<String>('cat-1')],
            )
            .get();

        final detail = plan.map((r) => r.data['detail'] as String).join(' | ');
        expect(detail, contains('idx_channels_category_name'));
      },
    );
  });
}
