import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_data/iptv_data.dart';
import 'package:iptv_data/testing.dart' as v1;

/// Migración v3 -> v4 (ADR-008, S5 · Ola 2): tabla nueva `epg_channels`
/// para el escritor XMLTV→drift. Mismo patrón que `migration_v3_test.dart`
/// (arnés `drift_dev schema dump` + verificación real de `onCreate` y
/// `onUpgrade`), ampliado con verificación en emulator Android CI
/// (`apps/app/integration_test/drift_migration_test.dart`, ADR-007 punto
/// 4).
void main() {
  group('migración v3 -> v4: epg_channels', () {
    test('una BD creada de cero (onCreate) trae epg_channels', () async {
      final db = IptvDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      // Fuerza la apertura real (createAll).
      await db.select(db.sources).get();

      final tableNames = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table'",
          )
          .get();
      expect(
        tableNames.map((r) => r.data['name'] as String),
        contains('epg_channels'),
      );
      expect(db.schemaVersion, 4);
    });

    test(
      'una BD migrada desde v1 (onUpgrade) también trae epg_channels, sin '
      'perder datos preexistentes',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'iptv_migration_v4_test_',
        );
        addTearDown(() async {
          if (tempDir.existsSync()) await tempDir.delete(recursive: true);
        });
        final file = File('${tempDir.path}/migration.sqlite');

        // Mismo patrón que `import_differential_test.dart`: materializa
        // el esquema v1 real, con una fila de datos reales, luego reabre
        // con el esquema actual y deja que `onUpgrade` haga su trabajo.
        final v1Db = v1.DatabaseAtV1(NativeDatabase(file));
        await v1Db.customStatement(
          'INSERT INTO channels (source_id, ref_key, content_type, name, url) '
          'VALUES (?, ?, ?, ?, ?)',
          ['s1', 'a', 'live', 'Canal preexistente', 'http://example.com/a'],
        );
        await v1Db.close();

        final migratedDb = IptvDatabase(NativeDatabase(file));
        addTearDown(migratedDb.close);

        final rows = await migratedDb.select(migratedDb.channels).get();
        expect(rows, hasLength(1));
        expect(rows.single.name, 'Canal preexistente');

        final tableNames = await migratedDb
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'table'",
            )
            .get();
        expect(
          tableNames.map((r) => r.data['name'] as String),
          contains('epg_channels'),
        );
        expect(migratedDb.schemaVersion, 4);

        // La tabla migrada debe ser funcional, no solo existir en el
        // esquema — un insert/select real la ejercita.
        await migratedDb
            .into(migratedDb.epgChannels)
            .insert(
              EpgChannelsCompanion.insert(
                tvgId: 'canal.1',
                displayNamesJson: '["Canal Uno"]',
                urlsJson: '[]',
              ),
            );
        final epgChannelRows = await migratedDb.select(migratedDb.epgChannels).get();
        expect(epgChannelRows, hasLength(1));
        expect(epgChannelRows.single.displayNamesJson, '["Canal Uno"]');
      },
    );
  });
}
