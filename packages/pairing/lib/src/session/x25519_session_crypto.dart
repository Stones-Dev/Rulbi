import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as crypto;

import 'session_crypto.dart';

/// Implementación **provisional** de [SessionCrypto] (ver la limitación
/// conocida documentada allí): X25519 (ECDH) + HKDF-SHA256 para derivar
/// la clave de sesión, AES-256-GCM (AEAD) para sellar/abrir. Apache-2.0
/// (P8), pura Dart — sin dependencia de Flutter.
final class X25519SessionCrypto implements SessionCrypto {
  const X25519SessionCrypto();

  static final _keyExchange = crypto.X25519();
  static final _hkdf = crypto.Hkdf(
    hmac: crypto.Hmac.sha256(),
    outputLength: 32,
  );
  static final _aead = crypto.AesGcm.with256bits();

  @override
  Future<KeyExchangeKeyPair> generateKeyPair() async {
    final keyPair = await _keyExchange.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    return KeyExchangeKeyPair(
      publicKey: Uint8List.fromList(publicKey.bytes),
      privateKey: EphemeralPrivateKeyHandle(keyPair),
    );
  }

  @override
  Future<SessionKey> deriveSessionKey({
    required EphemeralPrivateKeyHandle localPrivateKey,
    required Uint8List remotePublicKey,
    required String authFactor,
  }) async {
    final keyPair = localPrivateKey.value as crypto.SimpleKeyPair;
    final remote = crypto.SimplePublicKey(
      remotePublicKey,
      type: crypto.KeyPairType.x25519,
    );
    final shared = await _keyExchange.sharedSecretKey(
      keyPair: keyPair,
      remotePublicKey: remote,
    );
    final derived = await _hkdf.deriveKey(
      secretKey: shared,
      info: utf8.encode(authFactor),
    );
    return SessionKey(Uint8List.fromList(await derived.extractBytes()));
  }

  @override
  Future<Uint8List> seal(SessionKey key, Uint8List plaintext) async {
    final secretKey = crypto.SecretKey(key.bytes);
    final box = await _aead.encrypt(plaintext, secretKey: secretKey);
    return box.concatenation();
  }

  @override
  Future<Uint8List> open(SessionKey key, Uint8List ciphertext) async {
    final secretKey = crypto.SecretKey(key.bytes);
    try {
      final box = crypto.SecretBox.fromConcatenation(
        ciphertext,
        nonceLength: _aead.nonceLength,
        macLength: _aead.macAlgorithm.macLength,
      );
      final plain = await _aead.decrypt(box, secretKey: secretKey);
      return Uint8List.fromList(plain);
    } on crypto.SecretBoxAuthenticationError {
      throw SessionCryptoException(
        'Integridad inválida: clave equivocada o mensaje manipulado',
      );
    } on ArgumentError catch (e) {
      // Mensaje demasiado corto para ni siquiera contener nonce+mac.
      throw SessionCryptoException('Mensaje cifrado con formato inválido: $e');
    }
  }
}
