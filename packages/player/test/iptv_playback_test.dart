import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_playback/iptv_playback.dart';

void main() {
  test('exporta MediaKitPlayer/PlayerSurface/IptvPlayback', () {
    // Sanity de compilación/exportación — la cobertura de comportamiento
    // real de MediaKitPlayer no es posible en CI (necesita libmpv nativo,
    // ver docstring de la clase); esto solo confirma que el paquete se
    // resuelve y que los tres símbolos públicos existen.
    expect(MediaKitPlayer, isNotNull);
    expect(PlayerSurface, isNotNull);
    expect(IptvPlayback.ensureInitialized, isNotNull);
  });
}
