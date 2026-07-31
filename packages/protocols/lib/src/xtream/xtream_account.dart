/// Resultado de [XtreamClient.authenticate] — el equivalente Xtream de
/// "probar conexión" (ui-spec §2.9: estado de cuenta y caducidad antes de
/// guardar la fuente). `status` se conserva tal cual lo manda el panel
/// (no se normaliza a un enum cerrado): paneles distintos usan valores no
/// documentados fuera de `Active`/`Expired`/`Banned`/`Disabled`, y
/// perderlos sería tirar información real que la UI puede querer mostrar.
final class XtreamAccount {
  const XtreamAccount({
    required this.username,
    required this.status,
    required this.isTrial,
    required this.activeConnections,
    required this.maxConnections,
    this.expiresAt,
    this.allowedOutputFormats = const [],
  });

  final String username;

  /// Valor crudo de `user_info.status` (`"Active"`, `"Expired"`, ...).
  final String status;
  final bool isTrial;
  final int activeConnections;
  final int maxConnections;

  /// `null` si el panel no manda `exp_date` o lo manda vacío — una cuenta
  /// sin fecha de expiración no es un error (fixture real de T1.1).
  final DateTime? expiresAt;

  /// Formatos de salida que el panel permite (`m3u8`, `ts`, ...) — insumo
  /// de [XtreamUrlResolver] para decidir la extensión de un stream live.
  final List<String> allowedOutputFormats;

  @override
  String toString() => 'XtreamAccount($username, $status)';
}
