/// Puerto del almacén seguro de credenciales (P5): Keychain / Keystore /
/// DPAPI según la plataforma, implementado en `packages/data`. `core` no
/// sabe nada de la plataforma; solo pide y entrega secretos por
/// `sourceId`, nunca por el objeto `Source` completo (ver
/// `XtreamSourceConfig`).
abstract interface class SecureCredentialStore {
  Future<void> save(String sourceId, String secret);
  Future<String?> read(String sourceId);
  Future<void> delete(String sourceId);
}
