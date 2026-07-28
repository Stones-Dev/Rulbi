import '../entities/paired_device.dart';

abstract interface class PairedDeviceRepository {
  Future<List<PairedDevice>> getAll();
  Future<PairedDevice?> find(String deviceId);
  Future<void> upsert(PairedDevice device);
  Stream<List<PairedDevice>> watchAll();
}
