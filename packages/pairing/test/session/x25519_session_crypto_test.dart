import 'dart:convert';
import 'dart:typed_data';

import 'package:iptv_pairing/iptv_pairing.dart';
import 'package:test/test.dart';

/// Verifica la implementación real de `SessionCrypto` de forma aislada:
/// las máquinas de estado (`ReceiverSession`/`SenderSession`) se prueban
/// aparte contra un fake determinista — este archivo es la única prueba
/// de que X25519SessionCrypto en sí funciona.
void main() {
  const crypto = X25519SessionCrypto();

  test('el ECDH es simétrico: ambos lados derivan la misma clave', () async {
    final a = await crypto.generateKeyPair();
    final b = await crypto.generateKeyPair();

    final keyFromA = await crypto.deriveSessionKey(
      localPrivateKey: a.privateKey,
      remotePublicKey: b.publicKey,
      authFactor: 'mismo-factor',
    );
    final keyFromB = await crypto.deriveSessionKey(
      localPrivateKey: b.privateKey,
      remotePublicKey: a.publicKey,
      authFactor: 'mismo-factor',
    );

    expect(keyFromA.bytes, keyFromB.bytes);
  });

  test('un authFactor distinto deriva una clave distinta', () async {
    final a = await crypto.generateKeyPair();
    final b = await crypto.generateKeyPair();

    final keyOk = await crypto.deriveSessionKey(
      localPrivateKey: a.privateKey,
      remotePublicKey: b.publicKey,
      authFactor: 'correcto',
    );
    final keyWrong = await crypto.deriveSessionKey(
      localPrivateKey: a.privateKey,
      remotePublicKey: b.publicKey,
      authFactor: 'incorrecto',
    );

    expect(keyOk.bytes, isNot(equals(keyWrong.bytes)));
  });

  test('seal/open hacen un round-trip correcto', () async {
    final a = await crypto.generateKeyPair();
    final b = await crypto.generateKeyPair();
    final key = await crypto.deriveSessionKey(
      localPrivateKey: a.privateKey,
      remotePublicKey: b.publicKey,
      authFactor: 'factor',
    );

    final sealed = await crypto.seal(
      key,
      Uint8List.fromList(utf8.encode('hola mundo')),
    );
    final opened = await crypto.open(key, sealed);

    expect(utf8.decode(opened), 'hola mundo');
  });

  test('open lanza SessionCryptoException si la clave no coincide', () async {
    final a = await crypto.generateKeyPair();
    final b = await crypto.generateKeyPair();
    final c = await crypto.generateKeyPair();

    final keyAB = await crypto.deriveSessionKey(
      localPrivateKey: a.privateKey,
      remotePublicKey: b.publicKey,
      authFactor: 'factor',
    );
    final keyAC = await crypto.deriveSessionKey(
      localPrivateKey: a.privateKey,
      remotePublicKey: c.publicKey,
      authFactor: 'factor',
    );

    final sealed = await crypto.seal(
      keyAB,
      Uint8List.fromList(utf8.encode('secreto')),
    );

    expect(
      () => crypto.open(keyAC, sealed),
      throwsA(isA<SessionCryptoException>()),
    );
  });

  test(
    'open lanza SessionCryptoException si el mensaje fue manipulado',
    () async {
      final a = await crypto.generateKeyPair();
      final b = await crypto.generateKeyPair();
      final key = await crypto.deriveSessionKey(
        localPrivateKey: a.privateKey,
        remotePublicKey: b.publicKey,
        authFactor: 'factor',
      );

      final sealed = await crypto.seal(
        key,
        Uint8List.fromList(utf8.encode('mensaje original')),
      );
      final tampered = Uint8List.fromList(sealed)..[sealed.length - 1] ^= 0xFF;

      expect(
        () => crypto.open(key, tampered),
        throwsA(isA<SessionCryptoException>()),
      );
    },
  );
}
