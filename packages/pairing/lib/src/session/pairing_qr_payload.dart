/// Lanzada al leer un payload de QR de una versión futura que este
/// dispositivo no sabe interpretar.
final class UnsupportedPairingPayloadVersionException implements Exception {
  UnsupportedPairingPayloadVersionException(
    this.foundVersion,
    this.supportedVersion,
  );

  final int foundVersion;
  final int supportedVersion;

  @override
  String toString() =>
      'Payload de emparejamiento v$foundVersion; esta app solo entiende '
      'hasta v$supportedVersion.';
}

/// Payload del QR de emparejamiento (ui-spec §3.1, HU-08). **Nunca**
/// lleva credenciales — solo lo necesario para localizar al receptor y
/// un token efímero de un solo uso con TTL corto.
final class PairingQrPayload {
  const PairingQrPayload({
    required this.deviceName,
    required this.host,
    required this.port,
    required this.token,
  });

  static const currentVersion = 1;

  /// Claves que este payload puede llevar. Se expone para que los tests
  /// puedan comprobar la invariante "nunca hay credenciales" sin tener
  /// que adivinar el conjunto exacto de claves.
  static const allowedJsonKeys = {'v', 'app', 'name', 'host', 'port', 'tk'};

  final String deviceName;
  final String host;
  final int port;
  final String token;

  Map<String, Object?> toJson() => {
    'v': currentVersion,
    'app': 'iptv',
    'name': deviceName,
    'host': host,
    'port': port,
    'tk': token,
  };

  factory PairingQrPayload.fromJson(Map<String, Object?> json) {
    final version = json['v'] as int? ?? 1;
    if (version > currentVersion) {
      throw UnsupportedPairingPayloadVersionException(version, currentVersion);
    }
    return PairingQrPayload(
      deviceName: json['name'] as String,
      host: json['host'] as String,
      port: json['port'] as int,
      token: json['tk'] as String,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PairingQrPayload &&
      other.deviceName == deviceName &&
      other.host == host &&
      other.port == port &&
      other.token == token;

  @override
  int get hashCode => Object.hash(deviceName, host, port, token);

  @override
  String toString() => 'PairingQrPayload($deviceName, $host:$port)';
}
