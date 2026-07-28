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
/// `schemaVersion` empieza en 1 — el arnés de tests de migración
/// (`drift_dev schema dump/generate`) se monta desde ya para que las
/// migraciones de S2 en adelante sean baratas.
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
  int get schemaVersion => 1;

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
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
