import 'dart:convert';

/// Lanzada al escanear un código QR que no es un payload de emparejamiento
/// válido de esta app — cadena vacía, JSON con sintaxis rota, JSON que no
/// es un objeto, un objeto sin `app: "iptv"` (QR de otra cosa cualquiera:
/// wifi, una URL, otra app), o con campos ausentes o de tipo incorrecto.
///
/// Distinta de [UnsupportedPairingPayloadVersionException]: esa se lanza
/// cuando el QR **sí** es de este protocolo, solo que de una versión
/// futura — señal distinta de "esto no es un QR de emparejamiento en
/// absoluto" (S7 · Móvil base).
final class InvalidPairingQrCodeException implements Exception {
  const InvalidPairingQrCodeException(this.reason);

  /// Motivo interno, en inglés/técnico — no es texto de cara al usuario
  /// (RNF-09): la pantalla de escaneo decide su propio mensaje i18n con
  /// acción sugerida, este valor es solo para logs/depuración.
  final String reason;

  @override
  String toString() => 'InvalidPairingQrCodeException: $reason';
}

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

  /// Parsea la `String` cruda que devuelve un escáner de cámara (S7 · Móvil
  /// base) — [fromJson] solo entiende `Map`, y una lectura de QR entrega
  /// texto. Envuelve la validación en tres pasos, cada uno con su propio
  /// motivo de rechazo: (1) es JSON válido, (2) es un objeto con
  /// `app: "iptv"` — así se distingue un QR de otra app cualquiera de un
  /// bug real de parseo — y (3) delega en [fromJson] para el resto (versión
  /// soportada, campos con el tipo correcto).
  factory PairingQrPayload.fromQrString(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw const InvalidPairingQrCodeException('empty string');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(trimmed);
    } on FormatException {
      throw const InvalidPairingQrCodeException('not valid JSON');
    }

    if (decoded is! Map<String, Object?>) {
      throw const InvalidPairingQrCodeException('JSON value is not an object');
    }
    if (decoded['app'] != 'iptv') {
      throw const InvalidPairingQrCodeException('not an iptv pairing QR (app != "iptv")');
    }

    try {
      return PairingQrPayload.fromJson(decoded);
    } on TypeError {
      throw const InvalidPairingQrCodeException('missing or mistyped field');
    }
  }

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
