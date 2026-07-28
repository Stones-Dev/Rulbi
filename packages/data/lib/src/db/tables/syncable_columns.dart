import 'package:drift/drift.dart';

/// Mixin de las 4 tablas transferibles (plan §4.2, ADR-003): el mismo
/// contrato de tombstones que `Syncable` en `iptv_core`, a nivel de
/// columna SQL. Cada tabla que lo usa lleva además un índice sobre
/// `updated_at` (ver cada tabla) — el merge LWW de `pairing` pide "dame
/// lo cambiado desde X", y sin índice esa consulta sería un full scan.
mixin SyncableColumns on Table {
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
}
