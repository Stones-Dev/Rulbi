import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/features/settings/devices_screen.dart';
import 'package:iptv_app/l10n/app_localizations.dart';
import 'package:iptv_pairing/iptv_pairing.dart';

/// DevicesScreen (S7 · Móvil base, paso 4). Dos capas de cobertura
/// deliberadamente distintas:
///
/// - `classifyScannedQrCode` (función pura, sin `mobile_scanner`): prueba
///   que la pantalla traduce cada resultado de `PairingQrPayload
///   .fromQrString` a la fase correcta, sin cruzar los cables entre
///   `InvalidPairingQrCodeException`/`UnsupportedPairingPayloadVersionException`.
///   La clasificación de fondo (qué cadena produce qué excepción) ya está
///   cubierta por TDD en `packages/pairing`, no se repite aquí.
/// - Estado inicial del widget (`idle`): lo único verificable sin cámara
///   real — `MobileScanner` necesita un canal de plataforma que no existe
///   en `flutter_test` (mismo límite documentado en
///   `packages/player/test/iptv_playback_test.dart`). El flujo de escaneo
///   real se verifica en dispositivo, no aquí.
void main() {
  group('classifyScannedQrCode', () {
    test('QR de emparejamiento válido: ScanSuccess con el payload parseado', () {
      const payload = PairingQrPayload(
        deviceName: 'LG Salón',
        host: '192.168.1.34',
        port: 40123,
        token: 'un-token-efimero',
      );

      final outcome = classifyScannedQrCode(jsonEncode(payload.toJson()));

      expect(outcome, isA<ScanSuccess>());
      expect((outcome as ScanSuccess).payload, payload);
    });

    test('QR de otra app cualquiera: ScanInvalid', () {
      final outcome = classifyScannedQrCode(
        '{"type": "wifi", "ssid": "MiRed"}',
      );
      expect(outcome, isA<ScanInvalid>());
    });

    test('string vacía: ScanInvalid', () {
      expect(classifyScannedQrCode(''), isA<ScanInvalid>());
    });

    test('JSON con sintaxis rota: ScanInvalid', () {
      expect(classifyScannedQrCode('{"v": 1,'), isA<ScanInvalid>());
    });

    test('payload de emparejamiento de una versión futura: ScanUnsupportedVersion, no ScanInvalid', () {
      final outcome = classifyScannedQrCode(
        '{"v": ${PairingQrPayload.currentVersion + 1}, "app": "iptv", '
        '"name": "x", "host": "x", "port": 1, "tk": "t"}',
      );
      expect(outcome, isA<ScanUnsupportedVersion>());
    });
  });

  group('DevicesScreen', () {
    Widget wrap(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

    testWidgets('estado inicial: muestra el botón Escanear QR, ningún resultado todavía', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(const DevicesScreen()));
      await tester.pumpAndSettle();

      expect(find.byKey(DevicesScreen.scanQrButtonKey), findsOneWidget);
      expect(find.text('Scan QR'), findsOneWidget);
      expect(find.byKey(DevicesScreen.scanAgainButtonKey), findsNothing);
    });
  });
}
