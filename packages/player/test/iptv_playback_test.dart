import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_playback/iptv_playback.dart';

void main() {
  test('exporta MediaKitPlayer/PlayerSurface/IptvPlayback y AndroidMedia3', () {
    expect(MediaKitPlayer, isNotNull);
    expect(AndroidMedia3Player, isNotNull);
    expect(AndroidMedia3Surface, isNotNull);
    expect(PlayerSurface, isNotNull);
    expect(IptvPlayback.ensureInitialized, isNotNull);
    expect(IptvPlayback.createPlayer, isNotNull);
  });

  test(
    'IptvPlayback.ensureInitialized invoca el delegado en Windows/Linux, '
    'no en el resto (S7 · Móvil base — guardia de plataforma)',
    () {
      var called = false;
      IptvPlayback.ensureInitialized(ensureInitialized: () => called = true);

      // El runner de este test corre en la plataforma real (Windows/Linux
      // en dev y en CI, ver matrix de ci.yml) — se afirma contra
      // Platform.isWindows/isLinux en vez de fijar `true`/`false` a mano,
      // para que el test siga siendo correcto en ambos runners de CI sin
      // condicionales de plataforma en el propio test.
      expect(called, Platform.isWindows || Platform.isLinux);
    },
  );
}
