import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_core/iptv_core.dart';

/// Implementación real de `SecureCredentialStore` (P5) — el puerto vive en
/// `packages/core` desde S1 sin implementación hasta esta tarea (S4 · Ola
/// 2, Formulario Xtream). Sobre `flutter_secure_storage` (BSD-3, P8 ok):
/// Keychain en iOS/macOS, Keystore en Android (opciones por defecto — la
/// migración de `EncryptedSharedPreferences` a cifradores propios de la
/// librería es automática y transparente desde la v10, no algo que este
/// adaptador deba forzar), libsecret en Linux, DPAPI en Windows.
///
/// La clave real que llega a la plataforma nunca es `sourceId` a pelo —
/// va prefijada (`iptv.source_secret.<sourceId>`) para no colisionar con
/// ninguna otra clave que este mismo paquete guarde en el almacén seguro
/// en el futuro (p. ej. tokens de `pairing`, F6).
final class FlutterSecureCredentialStore implements SecureCredentialStore {
  FlutterSecureCredentialStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static String _key(String sourceId) => 'iptv.source_secret.$sourceId';

  @override
  Future<void> save(String sourceId, String secret) =>
      _storage.write(key: _key(sourceId), value: secret);

  @override
  Future<String?> read(String sourceId) => _storage.read(key: _key(sourceId));

  @override
  Future<void> delete(String sourceId) => _storage.delete(key: _key(sourceId));
}
