import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/shell/form_factor.dart';

void main() {
  tearDown(() {
    FormFactorDetector.overrideFormFactor = null;
    FormFactorDetector.setLeanbackForTesting(false);
  });

  test('overrideFormFactor tiene precedencia absoluta', () {
    FormFactorDetector.overrideFormFactor = FormFactor.tv;
    expect(FormFactorDetector.detect(), FormFactor.tv);

    FormFactorDetector.overrideFormFactor = FormFactor.mobile;
    expect(FormFactorDetector.detect(), FormFactor.mobile);

    FormFactorDetector.overrideFormFactor = FormFactor.desktop;
    expect(FormFactorDetector.detect(), FormFactor.desktop);
  });

  test('en plataforma desktop detecta desktop por defecto', () {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      expect(FormFactorDetector.detect(), FormFactor.desktop);
    }
  });

  test('setLeanbackForTesting cambia la detección en Android', () {
    FormFactorDetector.setLeanbackForTesting(true);
    FormFactorDetector.overrideFormFactor = FormFactor.tv;
    expect(FormFactorDetector.detect(), FormFactor.tv);

    FormFactorDetector.setLeanbackForTesting(false);
    FormFactorDetector.overrideFormFactor = FormFactor.mobile;
    expect(FormFactorDetector.detect(), FormFactor.mobile);
  });
}
