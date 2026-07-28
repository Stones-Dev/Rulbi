import 'dart:typed_data';

/// Material de una clave de sesión ya derivada — bytes opacos; nada fuera
/// de una implementación de [SessionCrypto] debe inspeccionarlos.
final class SessionKey {
  const SessionKey(this.bytes);
  final Uint8List bytes;
}

/// Handle opaco de la mitad privada de un par de claves de intercambio
/// efímero. Solo la implementación de [SessionCrypto] sabe qué hay
/// dentro; `ReceiverSession`/`SenderSession` lo pasan de un método a otro
/// sin mirarlo — así, cambiar de primitivo (ECDH por un PAKE, p. ej.) no
/// las obliga a cambiar.
final class EphemeralPrivateKeyHandle {
  const EphemeralPrivateKeyHandle(this.value);
  final Object value;
}

final class KeyExchangeKeyPair {
  const KeyExchangeKeyPair({required this.publicKey, required this.privateKey});
  final Uint8List publicKey;
  final EphemeralPrivateKeyHandle privateKey;
}

/// Lanzada cuando [SessionCrypto.open] no puede verificar la integridad
/// de un mensaje cifrado: clave equivocada, mensaje manipulado, o el
/// `authFactor` (token/código) no coincide en ambos lados.
final class SessionCryptoException implements Exception {
  SessionCryptoException(this.message);
  final String message;

  @override
  String toString() => 'SessionCryptoException: $message';
}

/// Puerto de la criptografía del protocolo de sesión (T1.7).
///
/// **Limitación conocida, documentada a propósito**: cuando el
/// `authFactor` es el código de 6 dígitos (~20 bits de entropía, el
/// flujo sin cámara), esta derivación por sí sola no impide un ataque de
/// diccionario *offline* sobre un handshake capturado — eso exigiría un
/// protocolo PAKE (p. ej. SPAKE2), que no se implementa todavía. Lo que
/// sí acota el riesgo hoy, con independencia del primitivo: el token es
/// de un solo uso, caduca a los 2 minutos, y la sesión se bloquea tras 3
/// intentos fallidos (`ReceiverSession`) — eso limita la ventana de
/// ataque *online*. La elección definitiva (mantener esta derivación,
/// migrar a un PAKE, o exigir siempre el QR de alta entropía para la
/// sync automática) se cierra en un ADR tras el spike S5; cambiar de
/// primitivo solo implica sustituir la implementación de este puerto.
abstract interface class SessionCrypto {
  Future<KeyExchangeKeyPair> generateKeyPair();

  /// Deriva la clave de sesión a partir del secreto compartido entre
  /// [localPrivateKey] y [remotePublicKey], usando [authFactor] (token
  /// del QR o código de 6 dígitos) como contexto de la derivación: liga
  /// la clave resultante a ese factor, de forma que un transcript
  /// capturado no sirve para autenticarse con un factor distinto.
  Future<SessionKey> deriveSessionKey({
    required EphemeralPrivateKeyHandle localPrivateKey,
    required Uint8List remotePublicKey,
    required String authFactor,
  });

  Future<Uint8List> seal(SessionKey key, Uint8List plaintext);

  /// Lanza [SessionCryptoException] si la integridad no verifica.
  Future<Uint8List> open(SessionKey key, Uint8List ciphertext);
}
