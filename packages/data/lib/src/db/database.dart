import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables/categories.dart';
import 'tables/channels.dart';
import 'tables/epg_programmes.dart';
import 'tables/favorites.dart';
import 'tables/paired_devices.dart';
import 'tables/sources.dart';
import 'tables/watch_state.dart';

part 'database.g.dart';

/// Esquema local (T1.5, plan §4.2): idéntico en todas las plataformas.
/// `schemaVersion` empezó en 1 (T1.5a); v2 (T1.6b) añade `deletedAt`/
/// `contentHash` a `channels` para el upsert diferencial. El snapshot de
/// v1 vive en `drift_schemas/drift_schema_v1.json` (volcado con
/// `drift_dev schema dump` **antes** de tocar la tabla — ver
/// `test/import_differential_test.dart`, test de migración), con su
/// helper generado expuesto vía `package:iptv_data/testing.dart`
/// (ADR-007: movido de `test/generated_migrations/` a
/// `lib/src/testing/` para que `apps/app/integration_test/` pueda
/// reutilizarlo). `drift_dev schema dump` sobre el `.dart` fuente falla
/// con el trigger `channels_fts_au`
/// (el analizador estático no resuelve `old`/`new` en su cuerpo — no es
/// un bug en la app: `database_test.dart` ya ejercita ese trigger vía
/// `db.update()` real y funciona); el snapshot de v1 se generó a partir
/// de un archivo `.sqlite` materializado con `IptvDatabase`, no del
/// código fuente.
@DriftDatabase(
  tables: [
    Sources,
    Categories,
    Channels,
    EpgProgrammes,
    Favorites,
    WatchState,
    PairedDevices,
  ],
  include: {'fts.drift'},
)
class IptvDatabase extends _$IptvDatabase {
  IptvDatabase(super.executor);

  /// Apertura real para producción: ruta correcta por plataforma
  /// (Windows/Linux/Android) vía `drift_flutter`, sin cablear
  /// `path_provider`/`sqlite3_flutter_libs` a mano.
  factory IptvDatabase.open() => IptvDatabase(driftDatabase(name: 'iptv'));

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    // `m.createAll()` crea las entidades en el orden de
    // `allSchemaEntities`, que no es un orden de dependencias: aquí
    // deja la tabla virtual FTS5 y sus triggers ANTES que `channels`,
    // y `CREATE TRIGGER ... ON channels` falla si `channels` no
    // existe todavía. Se crea a mano en el orden correcto: tablas
    // normales primero, luego la tabla virtual, luego índices y
    // triggers (que pueden referenciar cualquiera de las anteriores).
    onCreate: (m) async {
      final entities = allSchemaEntities.toList();
      for (final entity in entities.whereType<TableInfo<Table, Object?>>()) {
        if (entity is! VirtualTableInfo) await m.createTable(entity);
      }
      for (final entity
          in entities.whereType<VirtualTableInfo<Table, Object?>>()) {
        await m.createTable(entity);
      }
      for (final entity in entities.whereType<Index>()) {
        await m.createIndex(entity);
      }
      for (final entity in entities.whereType<Trigger>()) {
        await m.createTrigger(entity);
      }
    },
    // v1 -> v2 (T1.6b): tombstone local + hash de detección de cambios en
    // `channels`, para el upsert diferencial de `ManageSources`. Filas
    // existentes quedan con `deletedAt`/`contentHash` NULL — correcto:
    // ver el docstring de `ChannelsTable.contentHash`.
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(channels, channels.deletedAt);
        await m.addColumn(channels, channels.contentHash);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
