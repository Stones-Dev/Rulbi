import '../sync/syncable.dart';

/// Plataforma de un dispositivo emparejado (ui-spec §2.12). No incluye
/// iOS: fuera de la v1 (ver CLAUDE.md, plan.md rev. 1.2).
enum DevicePlatform { windows, linux, android, androidTv, fireTv, webos }

/// Un dispositivo con el que el usuario ha completado el emparejamiento
/// (HU-08). Entidad transferible: participa en la lista de "Dispositivos
/// emparejados" y en la sync automática (HU-09, S16+).
final class PairedDevice with Syncable {
  const PairedDevice({
    required this.deviceId,
    required this.name,
    required this.platform,
    required this.publicKey,
    required this.lastSeen,
    required this.updatedAt,
    this.autoSyncEnabled = false,
    this.deletedAt,
  });

  final String deviceId;
  final String name;
  final DevicePlatform platform;

  /// Clave pública para la sync automática entre dispositivos ya
  /// emparejados (S16+). No es secreta: no pasa por
  /// `SecureCredentialStore`.
  final String publicKey;
  final DateTime lastSeen;
  final bool autoSyncEnabled;

  @override
  final DateTime updatedAt;

  @override
  final DateTime? deletedAt;

  PairedDevice markDeleted(DateTime at) => PairedDevice(
    deviceId: deviceId,
    name: name,
    platform: platform,
    publicKey: publicKey,
    lastSeen: lastSeen,
    autoSyncEnabled: autoSyncEnabled,
    updatedAt: at,
    deletedAt: at,
  );

  PairedDevice withAutoSync(bool value, DateTime at) => PairedDevice(
    deviceId: deviceId,
    name: name,
    platform: platform,
    publicKey: publicKey,
    lastSeen: lastSeen,
    autoSyncEnabled: value,
    updatedAt: at,
    deletedAt: deletedAt,
  );

  PairedDevice seenAt(DateTime at) => PairedDevice(
    deviceId: deviceId,
    name: name,
    platform: platform,
    publicKey: publicKey,
    lastSeen: at,
    autoSyncEnabled: autoSyncEnabled,
    updatedAt: updatedAt,
    deletedAt: deletedAt,
  );

  @override
  bool operator ==(Object other) =>
      other is PairedDevice &&
      other.deviceId == deviceId &&
      other.name == name &&
      other.platform == platform &&
      other.publicKey == publicKey &&
      other.lastSeen == lastSeen &&
      other.autoSyncEnabled == autoSyncEnabled &&
      other.updatedAt == updatedAt &&
      other.deletedAt == deletedAt;

  @override
  int get hashCode => Object.hash(
    deviceId,
    name,
    platform,
    publicKey,
    lastSeen,
    autoSyncEnabled,
    updatedAt,
    deletedAt,
  );

  @override
  String toString() => 'PairedDevice($name, $platform)';
}
