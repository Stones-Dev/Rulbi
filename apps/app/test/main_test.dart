import 'package:iptv_app/main.dart';
import 'package:test/test.dart';

/// Verifica que `main()` arranca de verdad el motor de reproducción (S6,
/// política de wiring de CLAUDE.md, commit `0ddc345`) — no basta con que
/// `PlayerController`/`MediaKitPlayer` tengan tests unitarios en verde si
/// nada en el árbol real de la app los invoca (el mismo fallo que dejó
/// `PurgeScheduler` inerte durante S2-S5). No se llama a `main()` en sí
/// (invocaría `runApp` de verdad); se llama a `initializePlayback`, el
/// mismo punto que `main()` invoca, con un espía en vez del
/// `IptvPlayback.ensureInitialized` real (que exige libmpv nativo).
void main() {
  test('initializePlayback llama a ensureInitialized', () {
    var called = false;
    initializePlayback(ensureInitialized: () => called = true);
    expect(called, isTrue);
  });
}
