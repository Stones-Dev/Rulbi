import 'package:drift/drift.dart';

import 'syncable_columns.dart';

/// Espejo de `PairedDevice` (`iptv_core`, HU-08/09). Entidad
/// transferible; `publicKey` no es secreta (sync automática, S16+), no
/// pasa por el almacén seguro.
// `PairedDeviceRow`, no `PairedDevice`: evita colisión con la entidad
// homónima de iptv_core.
@DataClassName('PairedDeviceRow')
@TableIndex(name: 'idx_paired_devices_updated_at', columns: {#updatedAt})
class PairedDevices extends Table with SyncableColumns {
  TextColumn get deviceId => text()();
  TextColumn get name => text()();
  TextColumn get platform => text()();
  TextColumn get publicKey => text()();
  DateTimeColumn get lastSeen => dateTime()();
  BoolColumn get autoSyncEnabled =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {deviceId};
}
