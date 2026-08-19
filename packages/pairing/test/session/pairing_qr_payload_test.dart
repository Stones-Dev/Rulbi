import 'dart:convert';

import 'package:iptv_pairing/iptv_pairing.dart';
import 'package:test/test.dart';

void main() {
  test(
    'nunca lleva más claves que las del payload del QR (nunca credenciales)',
    () {
      const payload = PairingQrPayload(
        deviceName: 'LG Salón',
        host: '192.168.1.34',
        port: 40123,
        token: 'un-token-efimero',
      );

      // Fija el conjunto exacto de claves: si alguien añadiera un campo de
      // credencial al payload, este test lo señala en cuanto se toque
      // toJson(), sin depender de adivinar nombres de campo.
      expect(payload.toJson().keys.toSet(), PairingQrPayload.allowedJsonKeys);
      expect(PairingQrPayload.allowedJsonKeys, {
        'v',
        'app',
        'name',
        'host',
        'port',
        'tk',
      });
    },
  );

  test('round-trip preserva todos los campos', () {
    const payload = PairingQrPayload(
      deviceName: 'LG Salón',
      host: '192.168.1.34',
      port: 40123,
      token: 'un-token-efimero',
    );

    final decoded = PairingQrPayload.fromJson(payload.toJson());

    expect(decoded, payload);
  });

  test('rechaza con un error claro una versión mayor que la soportada', () {
    final json = const PairingQrPayload(
      deviceName: 'x',
      host: 'x',
      port: 1,
      token: 't',
    ).toJson();
    json['v'] = PairingQrPayload.currentVersion + 1;

    expect(
      () => PairingQrPayload.fromJson(json),
      throwsA(isA<UnsupportedPairingPayloadVersionException>()),
    );
  });

  // S7 · Móvil base — `fromQrString` es el escalón que le falta al parser
  // ya existente (`fromJson`, solo entiende `Map`) para consumir lo que un
  // escáner de cámara entrega de verdad: una `String` cruda, que puede ser
  // cualquier cosa. TDD estricto (P7): casos rotos primero.
  group('fromQrString', () {
    test('round-trip: decodifica el JSON serializado por toJson()', () {
      const payload = PairingQrPayload(
        deviceName: 'LG Salón',
        host: '192.168.1.34',
        port: 40123,
        token: 'un-token-efimero',
      );

      final decoded = PairingQrPayload.fromQrString(jsonEncode(payload.toJson()));

      expect(decoded, payload);
    });

    test('string vacía: InvalidPairingQrCodeException', () {
      expect(
        () => PairingQrPayload.fromQrString(''),
        throwsA(isA<InvalidPairingQrCodeException>()),
      );
    });

    test('solo espacios en blanco: InvalidPairingQrCodeException', () {
      expect(
        () => PairingQrPayload.fromQrString('   \n  '),
        throwsA(isA<InvalidPairingQrCodeException>()),
      );
    });

    test('JSON inválido (sintaxis rota): InvalidPairingQrCodeException', () {
      expect(
        () => PairingQrPayload.fromQrString('{"v": 1, "app": '),
        throwsA(isA<InvalidPairingQrCodeException>()),
      );
    });

    test('JSON válido pero no un objeto (array): InvalidPairingQrCodeException', () {
      expect(
        () => PairingQrPayload.fromQrString('[1, 2, 3]'),
        throwsA(isA<InvalidPairingQrCodeException>()),
      );
    });

    test('JSON válido pero no un objeto (string): InvalidPairingQrCodeException', () {
      expect(
        () => PairingQrPayload.fromQrString('"hola"'),
        throwsA(isA<InvalidPairingQrCodeException>()),
      );
    });

    test('objeto JSON de otra app cualquiera: InvalidPairingQrCodeException', () {
      // Un QR real de otra aplicación cualquiera — objeto JSON válido, sin
      // relación con el protocolo de emparejamiento de esta app.
      expect(
        () => PairingQrPayload.fromQrString(
          '{"type": "wifi", "ssid": "MiRed", "password": "secreta"}',
        ),
        throwsA(isA<InvalidPairingQrCodeException>()),
      );
    });

    test('objeto JSON con "app" distinto de "iptv": InvalidPairingQrCodeException', () {
      expect(
        () => PairingQrPayload.fromQrString(
          '{"v": 1, "app": "otra-app", "name": "x", "host": "x", "port": 1, "tk": "t"}',
        ),
        throwsA(isA<InvalidPairingQrCodeException>()),
      );
    });

    test('app "iptv" pero sin campo "name": InvalidPairingQrCodeException', () {
      expect(
        () => PairingQrPayload.fromQrString(
          '{"v": 1, "app": "iptv", "host": "192.168.1.34", "port": 40123, "tk": "t"}',
        ),
        throwsA(isA<InvalidPairingQrCodeException>()),
      );
    });

    test('app "iptv" pero "port" es un string en vez de un entero: InvalidPairingQrCodeException', () {
      expect(
        () => PairingQrPayload.fromQrString(
          '{"v": 1, "app": "iptv", "name": "x", "host": "x", "port": "40123", "tk": "t"}',
        ),
        throwsA(isA<InvalidPairingQrCodeException>()),
      );
    });

    test('app "iptv" con "v" de una versión futura: UnsupportedPairingPayloadVersionException, no InvalidPairingQrCodeException', () {
      // Sigue siendo un payload propio, bien formado, solo que de una
      // versión que este dispositivo aún no entiende — señal distinta de
      // "esto no es un QR de emparejamiento".
      expect(
        () => PairingQrPayload.fromQrString(
          '{"v": ${PairingQrPayload.currentVersion + 1}, "app": "iptv", '
          '"name": "x", "host": "x", "port": 1, "tk": "t"}',
        ),
        throwsA(isA<UnsupportedPairingPayloadVersionException>()),
      );
    });
  });
}
