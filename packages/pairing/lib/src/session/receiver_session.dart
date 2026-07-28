// El parámetro público se llama `crypto`/`clock` a propósito; el campo es
// privado (`_crypto`/`_clock`), y un initializing formal exigiría que
// coincidieran (`this._crypto` obligaría al parámetro con nombre a ser
// `_crypto`, invisible fuera de este archivo).
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:iptv_core/iptv_core.dart';

import '../config_package.dart';
import 'pairing_channel.dart';
import 'pairing_qr_payload.dart';
import 'pairing_session_errors.dart';
import 'pairing_session_state.dart';
import 'session_crypto.dart';
import 'six_digit_code.dart';
import 'wire.dart';

/// Rol "recibir configuración" del emparejamiento (ui-spec §2.12,
/// típicamente la TV). El token/código y el contador de intentos se
/// generan una vez en [startAdvertising] y se comparten entre todas las
/// conexiones entrantes que lleguen mientras dura la ventana de
/// `advertising` — más de un dispositivo puede intentar conectarse
/// (incluido, en el peor caso, un atacante probando el código), así que
/// el límite de intentos vive aquí, no por conexión.
final class ReceiverSession {
  ReceiverSession({
    required this.deviceName,
    required this.host,
    required this.port,
    required SessionCrypto crypto,
    required Clock clock,
    this.tokenTtl = const Duration(minutes: 2),
    this.maxAttempts = 3,
  }) : _crypto = crypto,
       _clock = clock;

  final String deviceName;
  final String host;
  final int port;
  final Duration tokenTtl;
  final int maxAttempts;

  final SessionCrypto _crypto;
  final Clock _clock;

  PairingSessionState _state = PairingSessionState.idle;
  PairingSessionState get state => _state;

  late final String _token;
  late final SixDigitCode _code;
  late final DateTime _tokenExpiresAt;
  bool _tokenConsumed = false;
  late int _remainingAttempts;
  KeyExchangeKeyPair? _keyPair;

  /// Genera token, código y el par de claves efímero. Debe llamarse una
  /// sola vez, antes de mostrar el QR/código en pantalla.
  Future<void> startAdvertising({
    String? tokenOverride,
    SixDigitCode? codeOverride,
  }) async {
    if (_state != PairingSessionState.idle) {
      throw StateError('startAdvertising ya se llamó en esta sesión');
    }
    _token = tokenOverride ?? _generateToken();
    _code = codeOverride ?? SixDigitCode.generate();
    _tokenExpiresAt = _clock.now().add(tokenTtl);
    _remainingAttempts = maxAttempts;
    _keyPair = await _crypto.generateKeyPair();
    _state = PairingSessionState.advertising;
  }

  PairingQrPayload get qrPayload {
    _requireAdvertising();
    return PairingQrPayload(
      deviceName: deviceName,
      host: host,
      port: port,
      token: _token,
    );
  }

  SixDigitCode get code {
    _requireAdvertising();
    return _code;
  }

  void _requireAdvertising() {
    if (_state == PairingSessionState.idle) {
      throw StateError('llama a startAdvertising() antes');
    }
  }

  /// Gestiona un intento de emparejamiento entrante sobre [channel].
  /// Se completa con el [ConfigPackage] recibido si el intento culmina
  /// en una transferencia, o lanza un [PairingSessionError] si se
  /// rechaza (factor incorrecto, token caducado/reutilizado, o intentos
  /// agotados). El merge con la configuración local (`LwwMerger`) es
  /// responsabilidad de quien llama — el trabajo de la sesión acaba en
  /// entregar el paquete verificado.
  Future<ConfigPackage> pair(PairingChannel channel) {
    final completer = Completer<ConfigPackage>();
    late final StreamSubscription<List<int>> subscription;
    SessionKey? sessionKey;

    void failAttempt(PairingSessionError error, {bool terminal = false}) {
      if (terminal) _state = PairingSessionState.failed;
      if (!completer.isCompleted) completer.completeError(error);
      unawaited(subscription.cancel());
    }

    Future<void> onMessage(List<int> bytes) async {
      final message = decodeMessage(bytes);
      switch (message['type']) {
        case 'hello':
          if (_tokenConsumed) {
            failAttempt(const PairingTokenAlreadyUsedError());
            return;
          }
          if (_clock.now().isAfter(_tokenExpiresAt)) {
            failAttempt(const PairingTokenExpiredError(), terminal: true);
            return;
          }
          if (_remainingAttempts <= 0) {
            failAttempt(const PairingAttemptsExceededError(), terminal: true);
            return;
          }

          final factorKind = message['factor'] as String;
          final authFactor = factorKind == 'code' ? _code.value : _token;
          final senderPublicKey = base64Decode(message['publicKey'] as String);

          final derived = await _crypto.deriveSessionKey(
            localPrivateKey: _keyPair!.privateKey,
            remotePublicKey: Uint8List.fromList(senderPublicKey),
            authFactor: authFactor,
          );
          sessionKey = derived;
          _state = PairingSessionState.challenged;
          final proof = await _crypto.seal(
            derived,
            Uint8List.fromList(utf8.encode(pairingConfirmationPhrase)),
          );
          channel.outgoing.add(
            encodeMessage({
              'type': 'challenge',
              'publicKey': base64Encode(_keyPair!.publicKey),
              'proof': base64Encode(proof),
            }),
          );
          return;

        case 'confirm':
          final key = sessionKey;
          if (key == null) return;
          try {
            final opened = await _crypto.open(
              key,
              Uint8List.fromList(base64Decode(message['proof'] as String)),
            );
            if (utf8.decode(opened) != pairingConfirmationPhrase) {
              throw SessionCryptoException('confirmación inesperada');
            }
          } on SessionCryptoException {
            _remainingAttempts--;
            failAttempt(
              _remainingAttempts <= 0
                  ? const PairingAttemptsExceededError()
                  : const PairingAuthFactorRejectedError(),
              terminal: _remainingAttempts <= 0,
            );
            return;
          }
          _tokenConsumed = true;
          _state = PairingSessionState.established;
          return;

        case 'reject':
          _remainingAttempts--;
          failAttempt(
            _remainingAttempts <= 0
                ? const PairingAttemptsExceededError()
                : const PairingAuthFactorRejectedError(),
            terminal: _remainingAttempts <= 0,
          );
          return;

        case 'payload':
          final key = sessionKey;
          if (key == null || !_tokenConsumed) return;
          _state = PairingSessionState.transferring;
          final opened = await _crypto.open(
            key,
            Uint8List.fromList(base64Decode(message['data'] as String)),
          );
          final json = jsonDecode(utf8.decode(opened)) as Map<String, Object?>;
          _state = PairingSessionState.done;
          if (!completer.isCompleted) {
            completer.complete(ConfigPackage.fromJson(json));
          }
          unawaited(subscription.cancel());
          return;
      }
    }

    subscription = channel.incoming.listen(onMessage);
    return completer.future;
  }

  static String _generateToken() {
    final rng = Random.secure();
    final bytes = Uint8List(16);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = rng.nextInt(256);
    }
    return base64UrlEncode(bytes);
  }
}
