import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Servicio para controlar el modo Picture-in-Picture (PiP) nativo en Android (S9).
abstract final class PipService {
  static const MethodChannel _channel =
      MethodChannel('com.stonesdev.iptv/pip');

  /// Consulta si el dispositivo Android soporta Picture-in-Picture (API 26+).
  static Future<bool> isPipSupported() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final result = await _channel.invokeMethod<bool>('isPipSupported');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Activa el modo Picture-in-Picture nativo.
  static Future<bool> enterPip() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final result = await _channel.invokeMethod<bool>('enterPip');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }
}
