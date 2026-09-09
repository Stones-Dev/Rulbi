import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Los tres layouts deliberados del proyecto (P2 de la constitution).
enum FormFactor { tv, mobile, desktop }

abstract final class FormFactorDetector {
  static const MethodChannel _channel =
      MethodChannel('com.stonesdev.iptv/form_factor');

  /// Flag cached tras inicialización asíncrona o detección de leanback.
  static bool _isLeanbackCached = false;

  /// Override explícito para tests y depuración.
  @visibleForTesting
  static FormFactor? overrideFormFactor;

  /// Inicializa la detección asíncrona de leanback en Android (S8 · TV base).
  /// Se invoca en `main()` antes de `runApp()`. Si falla o da timeout, cae a móvil.
  static Future<void> initialize({
    Duration timeout = const Duration(milliseconds: 500),
  }) async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final result = await _channel
            .invokeMethod<bool>('isLeanbackDevice')
            .timeout(timeout);
        _isLeanbackCached = result ?? false;
      } catch (_) {
        _isLeanbackCached = false;
      }
    }
  }

  /// Establece manualmente si el dispositivo actual es leanback / TV (para tests).
  @visibleForTesting
  static void setLeanbackForTesting(bool isLeanback) {
    _isLeanbackCached = isLeanback;
  }

  static FormFactor detect() {
    if (overrideFormFactor != null) {
      return overrideFormFactor!;
    }
    const envFormFactor = String.fromEnvironment('FORM_FACTOR');
    if (envFormFactor == 'tv') {
      return FormFactor.tv;
    } else if (envFormFactor == 'mobile') {
      return FormFactor.mobile;
    } else if (envFormFactor == 'desktop') {
      return FormFactor.desktop;
    }
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return FormFactor.desktop;
    }
    if (!kIsWeb && Platform.isAndroid) {
      if (_isLeanbackCached) {
        return FormFactor.tv;
      }
      return FormFactor.mobile;
    }
    return FormFactor.mobile;
  }
}
