import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_data/iptv_data.dart';
import 'package:iptv_data/testing.dart' as v1;

import 'support/v1_seed.dart';

/// ADR-007 — verificación de migraciones drift en Android runtime real
/// (no en el host, ver el ADR para las tres razones concretas por las
/// que un test de `packages/data` sobre `NativeDatabase` del host no
/// caza estos bugs). Alcance A+B: una BD v1 sembrada con datos reales
/// migra a v2 sin perder nada, y los repositorios siguen funcionando
/// sobre el esquema migrado — no solo humo de apertura.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('una BD v1 sembrada migra a v2 en runtime Android con datos '
      'intactos', (tester) async {
    // 0. `IptvDatabase.open()` (drift_flutter) no expone la ruta del
    // fichero que va a usar — se descubre en frío vía `PRAGMA
    // database_list` en vez de adivinarla, y se limpia después para
    // sembrar exactamente ahí.
    final probe = IptvDatabase.open();
    final databaseListRows = await probe
        .customSelect('PRAGMA database_list')
        .get();
    final mainRow = databaseListRows.firstWhere(
      (row) => row.data['name'] == 'main',
    );
    final dbPath = mainRow.data['file'] as String;
    await probe.close();

    for (final suffix in ['', '-wal', '-shm']) {
      final f = File('$dbPath$suffix');
      if (f.existsSync()) await f.delete();
    }

    // 1-2. Materializa el esquema v1 REAL (arnés de T1.6b, expuesto vía
    // `package:iptv_data/testing.dart` desde ADR-007) y siembra las ~24
    // filas de la matriz A+B (ver `support/v1_seed.dart`).
    final v1Db = v1.DatabaseAtV1(NativeDatabase(File(dbPath)));
    await seedV1Database(v1Db);
    await v1Db.close();

    // 3-4. Reabre el MISMO fichero con `IptvDatabase.open()` — el mismo
    // camino que usa producción (`drift_flutter`,
    // `NativeDatabase.createBackgroundConnection`, crítico según T1.5b)
    // — debe migrar sola vía `MigrationStrategy.onUpgrade`.
    final migratedDb = IptvDatabase.open();
    addTearDown(migratedDb.close);

    final channelRepository = DriftChannelRepository(migratedDb);
    final favoritesRepository = DriftFavoritesRepository(migratedDb);
    final watchStateRepository = DriftWatchStateRepository(migratedDb);

    // --- Migración estructural ---
    expect(migratedDb.schemaVersion, 2);
    final userVersionRow = await migratedDb
        .customSelect('PRAGMA user_version')
        .getSingle();
    expect(userVersionRow.data['user_version'], 2);

    final foreignKeysRow = await migratedDb
        .customSelect('PRAGMA foreign_keys')
        .getSingle();
    expect(foreignKeysRow.data['foreign_keys'], 1);

    // Dato que motiva la razón nº1 del ADR (versión de SQLite embebida
    // por `sqlite3_flutter_libs` en Android, no la del host) — se deja
    // en el log del job en cada corrida, sin coste de mantenerlo.
    final sqliteVersionRow = await migratedDb
        .customSelect('SELECT sqlite_version() AS v')
        .getSingle();
    debugPrint(
      'ADR-007: SQLite embebida en runtime Android = '
      '${sqliteVersionRow.data['v']}',
    );

    // --- Recuentos por tabla (exactos, contra lo sembrado) ---
    final allChannels = await migratedDb.select(migratedDb.channels).get();
    expect(allChannels, hasLength(expectedChannelCount));

    final favoriteRows = await migratedDb.select(migratedDb.favorites).get();
    expect(favoriteRows, hasLength(expectedFavoriteCount));

    final watchStateRows = await migratedDb.select(migratedDb.watchState).get();
    expect(watchStateRows, hasLength(expectedWatchStateCount));

    final sourceRows = await migratedDb.select(migratedDb.sources).get();
    expect(sourceRows, hasLength(expectedSourceCount));

    final categoryRows = await migratedDb.select(migratedDb.categories).get();
    expect(categoryRows, hasLength(expectedCategoryCount));

    // --- Contenido literal ---
    final c05Row =
        await (migratedDb.select(migratedDb.channels)
              ..where((c) => c.sourceId.equals('s1') & c.refKey.equals('c05')))
            .getSingle();
    expect(c05Row.name, 'España Directo');
    expect(c05Row.contentType, 'live');
    expect(c05Row.categoryId, 'cat-news');
    expect(c05Row.url, 'http://example.com/s1/c05');
    expect(c05Row.metadataJson, '{}');

    final c01WatchState =
        await (migratedDb.select(migratedDb.watchState)
              ..where((w) => w.sourceId.equals('s1') & w.refKey.equals('c01')))
            .getSingle();
    expect(c01WatchState.positionMs, c01PositionMs);
    expect(c01WatchState.durationMs, c01DurationMs);

    const s1c05 = ChannelRef(sourceId: 's1', key: 'c05');
    final c05Favorite = await favoritesRepository.find(s1c05);
    expect(c05Favorite, isNotNull);
    expect(c05Favorite!.isDeleted, isTrue);

    for (final ref in const [
      ChannelRef(sourceId: 's1', key: 'c01'),
      ChannelRef(sourceId: 's1', key: 'c02'),
      ChannelRef(sourceId: 's2', key: 'c01'),
    ]) {
      final favorite = await favoritesRepository.find(ref);
      expect(
        favorite,
        isNotNull,
        reason: '$ref debería seguir siendo favorito',
      );
      expect(favorite!.isDeleted, isFalse);
    }

    // Aislamiento por fuente: mismo refKey, sourceId distinto.
    expect(
      await favoritesRepository.find(
        const ChannelRef(sourceId: 's2', key: 'c02'),
      ),
      isNull,
    );

    // --- Columnas nuevas de v2: NULL, no 0 ni cadena vacía (política
    // documentada en el docstring de `Channels.contentHash`) ---
    for (final row in allChannels) {
      expect(row.deletedAt, isNull, reason: '${row.refKey}.deletedAt');
      expect(row.contentHash, isNull, reason: '${row.refKey}.contentHash');
    }

    // --- FTS5 tras la migración: `remove_diacritics 2` en la SQLite
    // embebida real de Android, no solo en la del host ---
    final espanaResults = await channelRepository.search('espana');
    expect(espanaResults.map((c) => c.ref.key), contains('c05'));

    final nanduResults = await channelRepository.search('nandu');
    expect(nanduResults.map((c) => c.ref.key), contains('c06'));

    await migratedDb.customStatement(
      "INSERT INTO channels_fts(channels_fts) VALUES('integrity-check')",
    );

    // --- Ejercicio real de repositorios sobre el esquema migrado ---
    Channel liveChannel({
      required String sourceId,
      required String refKey,
      String? categoryId,
      String name = 'Canal',
    }) => Channel(
      ref: ChannelRef(sourceId: sourceId, key: refKey),
      sourceId: sourceId,
      categoryId: categoryId,
      type: ContentType.live,
      name: name,
      url: Uri.parse('http://example.com/$sourceId/$refKey'),
    );

    // Reimporta s1 con los 10 preexistentes + un canal nuevo (c11): los
    // 10 preexistentes cuentan como `updated`, no `unchanged` — su
    // `contentHash` es NULL (vienen de v1), y sin un hash previo real no
    // hay forma honesta de decir que "no cambiaron" (política del
    // esquema, ver docstring de `Channels.contentHash`).
    final s1RefKeys = seedChannels
        .where((c) => c.sourceId == 's1')
        .map((c) => c.refKey)
        .toList();
    Stream<Channel> s1Stream({required bool includeC11}) =>
        Stream.fromIterable([
          for (final refKey in s1RefKeys)
            liveChannel(
              sourceId: 's1',
              refKey: refKey,
              categoryId: seedChannels
                  .firstWhere((c) => c.sourceId == 's1' && c.refKey == refKey)
                  .categoryId,
              name: seedChannels
                  .firstWhere((c) => c.sourceId == 's1' && c.refKey == refKey)
                  .name,
            ),
          if (includeC11)
            liveChannel(sourceId: 's1', refKey: 'c11', name: 'Canal Once'),
        ]);

    final firstReimport = await channelRepository.importSourceContent(
      's1',
      s1Stream(includeC11: true),
      now: DateTime.utc(2026, 2, 1),
    );
    expect(firstReimport.inserted, 1);
    expect(firstReimport.updated, s1RefKeys.length);
    expect(firstReimport.unchanged, 0);

    final secondReimport = await channelRepository.importSourceContent(
      's1',
      s1Stream(includeC11: true),
      now: DateTime.utc(2026, 2, 2),
    );
    expect(secondReimport.unchanged, s1RefKeys.length + 1);
    expect(secondReimport.updated, 0);
    expect(secondReimport.inserted, 0);

    final thirdReimport = await channelRepository.importSourceContent(
      's1',
      s1Stream(includeC11: false),
      now: DateTime.utc(2026, 2, 3),
    );
    expect(thirdReimport.tombstoned, 1);

    final c11SearchAfterTombstone = await channelRepository.search('once');
    expect(c11SearchAfterTombstone, isEmpty);

    const s1c11 = ChannelRef(sourceId: 's1', key: 'c11');
    await favoritesRepository.upsert(
      Favorite(channel: s1c11, updatedAt: DateTime.utc(2026, 2, 3)),
    );
    expect((await favoritesRepository.find(s1c11))?.isDeleted, isFalse);

    await watchStateRepository.upsert(
      WatchState(
        channel: s1c11,
        position: const Duration(milliseconds: 42000),
        duration: Duration.zero,
        updatedAt: DateTime.utc(2026, 2, 3),
      ),
    );
    final c11WatchState = await watchStateRepository.find(s1c11);
    expect(c11WatchState?.position, const Duration(milliseconds: 42000));

    // Segunda `integrity-check` de FTS5 tras todas las escrituras.
    await migratedDb.customStatement(
      "INSERT INTO channels_fts(channels_fts) VALUES('integrity-check')",
    );
  });
}
