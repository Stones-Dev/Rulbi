import 'package:drift/drift.dart';
import 'package:iptv_core/iptv_core.dart';

import '../db/database.dart';

final class DriftPairedDeviceRepository implements PairedDeviceRepository {
  DriftPairedDeviceRepository(this._db);

  final IptvDatabase _db;

  @override
  Future<List<PairedDevice>> getAll() async {
    final rows = await _db.select(_db.pairedDevices).get();
    return rows.map(_toEntity).toList();
  }

  @override
  Future<PairedDevice?> find(String deviceId) async {
    final row = await (_db.select(
      _db.pairedDevices,
    )..where((d) => d.deviceId.equals(deviceId))).getSingleOrNull();
    return row == null ? null : _toEntity(row);
  }

  @override
  Future<void> upsert(PairedDevice device) {
    return _db
        .into(_db.pairedDevices)
        .insertOnConflictUpdate(_toCompanion(device));
  }

  @override
  Stream<List<PairedDevice>> watchAll() {
    return _db
        .select(_db.pairedDevices)
        .watch()
        .map((rows) => rows.map(_toEntity).toList());
  }

  PairedDevice _toEntity(PairedDeviceRow row) => PairedDevice(
    deviceId: row.deviceId,
    name: row.name,
    platform: DevicePlatform.values.byName(row.platform),
    publicKey: row.publicKey,
    lastSeen: row.lastSeen,
    autoSyncEnabled: row.autoSyncEnabled,
    updatedAt: row.updatedAt,
    deletedAt: row.deletedAt,
  );

  PairedDevicesCompanion _toCompanion(PairedDevice device) =>
      PairedDevicesCompanion.insert(
        deviceId: device.deviceId,
        name: device.name,
        platform: device.platform.name,
        publicKey: device.publicKey,
        lastSeen: device.lastSeen,
        autoSyncEnabled: Value(device.autoSyncEnabled),
        updatedAt: Value(device.updatedAt),
        deletedAt: Value(device.deletedAt),
      );
}
