import 'dart:io';

/// Los tres layouts deliberados del proyecto (P2 de la constitution).
enum FormFactor { tv, mobile, desktop }

abstract final class FormFactorDetector {
  static FormFactor detect() {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return FormFactor.desktop;
    }
    if (Platform.isAndroid) {
      // TODO: detectar el feature "leanback" real (Android TV / Fire TV) vía
      // platform channel. Hasta entonces, todo Android se trata como móvil.
      // Ver spike S1 y F3 en .specify/tasks.md.
      return FormFactor.mobile;
    }
    return FormFactor.mobile;
  }
}
