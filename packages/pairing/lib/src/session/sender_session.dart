// El parámetro público se llama `channel`/`crypto` a propósito; el campo
// es privado (`_channel`/`_crypto`), y un initializing formal exigiría
// que coincidieran (ver receiver_session.dart).
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../config_package.dart';
import 'pairing_channel.dart';
import 'pairing_session_errors.dart';
import 'pairing_session_state.dart';
import 'session_crypto.dart';
import 'wire.dart';

/// Rol "enviar configuración" del emparejamiento (ui-spec §2.12,
/// típicamente el móvil/PC). Una instancia sirve para un único intento:
/// si el código/token no coincide con el del receptor, se crea una
/// instancia nueva para reintentar (mismo patrón que pedirle al usuario
/// que vuelva a teclear el código).
final class SenderSession {
  SenderSession({
    required PairingChannel channel,
    required SessionCrypto crypto,
  }) : _channel = channel,
       _crypto = crypto;

  final PairingChannel _channel;
  final SessionCrypto _crypto;

  PairingSessionState _state = PairingSessionState.idle;
  PairingSessionState get state => _state;

  KeyExchangeKeyPair? _keyPair;
  String? _authFactor;
  SessionKey? _sessionKey;
  StreamSubscription<List<int>>? _subscription;
  final Completer<void> _establishment = Completer<void>();

  /// Inicia el emparejamiento con el token leído del QR escaneado.
  Future<void> pairWithToken(String token) => _pair(token, 'token');

  /// Inicia el emparejamiento con el código de 6 dígitos tecleado.
  Future<void> pairWithCode(String code) => _pair(code, 'code');

  Future<void> _pair(String authFactor, String factorKind) async {
    if (_state != PairingSessionState.idle) {
      throw StateError(
        'esta sesión ya inició un intento; crea una nueva para reintentar',
      );
    }
    _authFactor = authFactor;
    _keyPair = await _crypto.generateKeyPair();
    _state = PairingSessionState.challenged;
    _subscription = _channel.incoming.listen(_onMessage);
    _channel.outgoing.add(
      encodeMessage({
        'type': 'hello',
        'publicKey': base64Encode(_keyPair!.publicKey),
        'factor': factorKind,
      }),
    );
  }

  /// Se completa cuando el receptor confirma la clave de sesión. Lanza
  /// [PairingAuthFactorRejectedError] si el código/token tecleado no
  /// coincidía con el del receptor.
  Future<void> get established => _establishment.future;

  /// Cifra y envía el paquete de configuración. Solo válido una vez
  /// [established] se ha completado.
  Future<void> sendConfig(ConfigPackage package) async {
    if (_state != PairingSessionState.established) {
      throw StateError('la sesión no está establecida todavía');
    }
    final sessionKey = _sessionKey!;
    final json = jsonEncode(package.toJsonForSecureChannel());
    final sealed = await _crypto.seal(
      sessionKey,
      Uint8List.fromList(utf8.encode(json)),
    );
    _state = PairingSessionState.transferring;
    _channel.outgoing.add(
      encodeMessage({'type': 'payload', 'data': base64Encode(sealed)}),
    );
    _state = PairingSessionState.done;
    await _subscription?.cancel();
  }

  Future<void> _onMessage(List<int> bytes) async {
    final message = decodeMessage(bytes);
    if (message['type'] != 'challenge' ||
        _state != PairingSessionState.challenged) {
      return;
    }

    final receiverPublicKey = base64Decode(message['publicKey'] as String);
    final proof = base64Decode(message['proof'] as String);

    final sessionKey = await _crypto.deriveSessionKey(
      localPrivateKey: _keyPair!.privateKey,
      remotePublicKey: Uint8List.fromList(receiverPublicKey),
      authFactor: _authFactor!,
    );

    try {
      final opened = await _crypto.open(sessionKey, Uint8List.fromList(proof));
      if (utf8.decode(opened) != pairingConfirmationPhrase) {
        throw SessionCryptoException('confirmación inesperada');
      }
    } on SessionCryptoException {
      _state = PairingSessionState.failed;
      _channel.outgoing.add(
        encodeMessage({
          'type': 'reject',
          'reason': 'código o token incorrecto',
        }),
      );
      if (!_establishment.isCompleted) {
        _establishment.completeError(const PairingAuthFactorRejectedError());
      }
      await _subscription?.cancel();
      return;
    }

    _sessionKey = sessionKey;
    _state = PairingSessionState.established;
    final ack = await _crypto.seal(
      sessionKey,
      Uint8List.fromList(utf8.encode(pairingConfirmationPhrase)),
    );
    _channel.outgoing.add(
      encodeMessage({'type': 'confirm', 'proof': base64Encode(ack)}),
    );
    if (!_establishment.isCompleted) {
      _establishment.complete();
    }
  }
}
