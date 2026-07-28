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
}
