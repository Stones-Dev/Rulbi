import 'package:flutter/material.dart';
import 'package:iptv_pairing/iptv_pairing.dart';
import 'package:iptv_tokens/iptv_tokens.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../l10n/app_localizations.dart';

/// Resultado de clasificar el texto crudo de una detección de cámara.
/// Función pura (sin Flutter, sin `mobile_scanner`), extraída aparte de
/// `_onDetect` para que el mapeo "string cruda → resultado" sea testeable
/// con un `BarcodeCapture` sintético sin necesitar un canal de plataforma
/// de cámara real — mismo límite ya documentado en
/// `packages/player/test/iptv_playback_test.dart` (S7 · Móvil base). La
/// clasificación en sí (qué excepción de `PairingQrPayload.fromQrString`
/// implica qué) ya está cubierta por TDD en `packages/pairing`; esto solo
/// prueba que `DevicesScreen` la traduce a fase de pantalla sin cruzar los
/// cables.
sealed class ScanOutcome {
  const ScanOutcome();
}

final class ScanSuccess extends ScanOutcome {
  const ScanSuccess(this.payload);
  final PairingQrPayload payload;
}

final class ScanInvalid extends ScanOutcome {
  const ScanInvalid();
}

final class ScanUnsupportedVersion extends ScanOutcome {
  const ScanUnsupportedVersion();
}

@visibleForTesting
ScanOutcome classifyScannedQrCode(String raw) {
  try {
    return ScanSuccess(PairingQrPayload.fromQrString(raw));
  } on UnsupportedPairingPayloadVersionException {
    return const ScanUnsupportedVersion();
  } on InvalidPairingQrCodeException {
    return const ScanInvalid();
  }
}

/// Fase local de la pantalla — puramente de presentación (no hay providers
/// implicados, mismo criterio que `_isProbing`/`_probeResult` de los
/// formularios de fuentes): esta pantalla no persiste nada, solo escanea y
/// muestra.
enum _ScanPhase { idle, scanning, result, invalidQr, unsupportedVersion }

/// Escáner QR base (ui-spec §2.12/§3.1, S7 · Móvil base, paso 4) —
/// **"aún sin destino"** por diseño explícito del DoD del sprint: escanea,
/// parsea el payload con [PairingQrPayload.fromQrString] y lo muestra en
/// pantalla (nombre, host, puerto). No abre canal, no envía nada, no
/// persiste `paired_devices` — el flujo de envío completo (§2.12 "Enviar
/// configuración") es de un sprint posterior. El **token nunca se muestra**
/// (P5): es un secreto efímero de un solo uso.
class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  static const scanQrButtonKey = Key('devicesScreen.scanQrButton');
  static const scanAgainButtonKey = Key('devicesScreen.scanAgainButton');
  static const cancelScanButtonKey = Key('devicesScreen.cancelScanButton');

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  _ScanPhase _phase = _ScanPhase.idle;
  PairingQrPayload? _result;

  // `onDetect` puede disparar más de una vez para el mismo QR mientras el
  // frame anterior todavía no ha desmontado `MobileScanner` (varias
  // detecciones en vuelo) — sin esta guardia, un segundo evento tras el
  // primero válido podría pisar el `setState` que ya cambió de fase.
  bool _handledDetection = false;

  void _startScanning() {
    setState(() {
      _phase = _ScanPhase.scanning;
      _result = null;
      _handledDetection = false;
    });
  }

  void _cancelScanning() {
    setState(() => _phase = _ScanPhase.idle);
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handledDetection || capture.barcodes.isEmpty) return;
    final raw = capture.barcodes.first.rawValue;
    if (raw == null) return;

    _handledDetection = true;
    switch (classifyScannedQrCode(raw)) {
      case ScanSuccess(:final payload):
        setState(() {
          _phase = _ScanPhase.result;
          _result = payload;
        });
      case ScanUnsupportedVersion():
        setState(() => _phase = _ScanPhase.unsupportedVersion);
      case ScanInvalid():
        setState(() => _phase = _ScanPhase.invalidQr);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: IptvColors.background,
      appBar: AppBar(
        backgroundColor: IptvColors.surface,
        title: Text(l10n.navDevices),
        leading: _phase == _ScanPhase.scanning
            ? IconButton(
                key: DevicesScreen.cancelScanButtonKey,
                icon: const Icon(Icons.close),
                tooltip: l10n.commonCancel,
                onPressed: _cancelScanning,
              )
            : null,
      ),
      body: switch (_phase) {
        _ScanPhase.idle => _IdleState(onScan: _startScanning),
        _ScanPhase.scanning => MobileScanner(
          controller: MobileScannerController(
            formats: const [BarcodeFormat.qrCode],
          ),
          onDetect: _onDetect,
          errorBuilder: (context, exception) =>
              _CameraError(exception: exception, onRetry: _startScanning),
        ),
        _ScanPhase.result => _ResultState(
          payload: _result!,
          onScanAgain: _startScanning,
        ),
        _ScanPhase.invalidQr => _ErrorState(
          message: l10n.devicesScanInvalidQr,
          onRetry: _startScanning,
        ),
        _ScanPhase.unsupportedVersion => _ErrorState(
          message: l10n.devicesScanUnsupportedVersion,
          onRetry: _startScanning,
        ),
      },
    );
  }
}

class _IdleState extends StatelessWidget {
  const _IdleState({required this.onScan});

  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(IptvSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Symbols.qr_code_scanner_rounded,
              size: IptvIconSizes.hero,
              color: IptvColors.textSecondary,
            ),
            const SizedBox(height: IptvSpacing.md),
            Text(
              l10n.devicesScanHint,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: IptvColors.textSecondary),
            ),
            const SizedBox(height: IptvSpacing.lg),
            FilledButton(
              key: DevicesScreen.scanQrButtonKey,
              onPressed: onScan,
              child: Text(l10n.devicesScanQrButton),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultState extends StatelessWidget {
  const _ResultState({required this.payload, required this.onScanAgain});

  final PairingQrPayload payload;
  final VoidCallback onScanAgain;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(IptvSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Symbols.devices_rounded,
              size: IptvIconSizes.hero,
              color: IptvColors.accent,
            ),
            const SizedBox(height: IptvSpacing.md),
            Text(
              l10n.devicesScanResultTitle,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(color: IptvColors.textPrimary),
            ),
            const SizedBox(height: IptvSpacing.sm),
            // Nombre/host/puerto — nunca el token (P5, docstring de la
            // clase).
            Text(
              l10n.devicesScanResultDetails(
                payload.deviceName,
                payload.host,
                payload.port,
              ),
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: IptvColors.textSecondary),
            ),
            const SizedBox(height: IptvSpacing.lg),
            FilledButton(
              key: DevicesScreen.scanAgainButtonKey,
              onPressed: onScanAgain,
              child: Text(l10n.devicesScanAgainButton),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(IptvSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              size: IptvIconSizes.hero,
              color: IptvColors.error,
            ),
            const SizedBox(height: IptvSpacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: IptvColors.textSecondary),
            ),
            const SizedBox(height: IptvSpacing.lg),
            FilledButton(
              key: DevicesScreen.scanAgainButtonKey,
              onPressed: onRetry,
              child: Text(l10n.devicesScanAgainButton),
            ),
          ],
        ),
      ),
    );
  }
}

/// `errorBuilder` de `MobileScanner` — cubre el permiso de cámara denegado
/// (RNF-09: acción sugerida, no un código de error) y cualquier otro fallo
/// de inicialización de la cámara con el mismo patrón de reintento.
class _CameraError extends StatelessWidget {
  const _CameraError({required this.exception, required this.onRetry});

  final MobileScannerException exception;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final message = exception.errorCode == MobileScannerErrorCode.permissionDenied
        ? l10n.devicesScanCameraPermissionDenied
        : l10n.devicesScanCameraError;
    return _ErrorState(message: message, onRetry: onRetry);
  }
}
