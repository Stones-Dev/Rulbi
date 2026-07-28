import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:iptv_pairing/iptv_pairing.dart';

/// Fake determinista de [SessionCrypto] para los tests de las máquinas
/// de estado (`ReceiverSession`/`SenderSession`, T1.7): sin esto, cada
/// test dependería de la implementación real (`X25519SessionCrypto`,
/// probada aparte en `x25519_session_crypto_test.dart`) y sería más
/// lento y menos legible sobre qué invariante del *protocolo* se está
/// verificando.
///
/// Simula la simetría de un ECDH real (ambos lados derivan la misma
/// clave a partir de su propia privada y la pública del otro) haciendo
/// que la "pública" de un par lleve el mismo identificador que su
/// "privada": derivar con cualquiera de los dos lados, en cualquier
/// orden, produce la misma clave para el mismo `authFactor`.
final class FakeSessionCrypto implements SessionCrypto {
  int _counter = 0;

  @override
  Future<KeyExchangeKeyPair> generateKeyPair() async {
    _counter += 1;
    final id = 'k$_counter';
    return KeyExchangeKeyPair(
      publicKey: Uint8List.fromList(utf8.encode(id)),
      privateKey: EphemeralPrivateKeyHandle(id),
    );
  }

  @override
  Future<SessionKey> deriveSessionKey({
    required EphemeralPrivateKeyHandle localPrivateKey,
    required Uint8List remotePublicKey,
    required String authFactor,
  }) async {
    final myId = localPrivateKey.value as String;
    final peerId = utf8.decode(remotePublicKey);
    final parts = [myId, peerId]..sort();
    final material = utf8.encode('${parts.join('|')}|$authFactor');
    return SessionKey(Uint8List.fromList(hash.sha256.convert(material).bytes));
  }

  @override
  Future<Uint8List> seal(SessionKey key, Uint8List plaintext) async {
    return Uint8List.fromList([...key.bytes.take(4), ...plaintext]);
  }

  @override
  Future<Uint8List> open(SessionKey key, Uint8List ciphertext) async {
    if (ciphertext.length < 4) {
      throw SessionCryptoException('mensaje demasiado corto');
    }
    final tag = ciphertext.sublist(0, 4);
    final expectedTag = key.bytes.take(4).toList();
    for (var i = 0; i < 4; i++) {
      if (tag[i] != expectedTag[i]) {
        throw SessionCryptoException('etiqueta de integridad inválida');
      }
    }
    return Uint8List.fromList(ciphertext.sublist(4));
  }
}
