import 'package:iptv_protocols/src/xtream/xtream_transport.dart';
import 'package:test/test.dart';

import 'support/fake_xtream_transport.dart';

/// T1.4: el rate limiting de un panel Xtream (encargo original — "algunos
/// paneles limitan agresivamente") se resuelve en `RetryingXtreamTransport`,
/// probado aquí con reloj falso: ningún test de esta batería duerme de
/// verdad ni toca la red (los fixtures son offline, tal como pide el
/// encargo).
void main() {
  group('RetryingXtreamTransport', () {
    test('reintenta un 429 con Retry-After y devuelve la respuesta buena', () async {
      final fake = FakeXtreamTransport()
        ..enqueue('auth', rawResponse([], statusCode: 429, retryAfter: const Duration(seconds: 2)))
        ..enqueue('auth', jsonResponse({'user_info': null}));

      final waits = <Duration>[];
      final retrying = RetryingXtreamTransport(
        fake,
        sleep: (d) async {
          waits.add(d);
        },
      );

      final response = await retrying.get(Uri.parse('http://h/player_api.php?action=auth'));

      expect(response.statusCode, 200);
      expect(waits, [const Duration(seconds: 2)]);
      expect(fake.callCount('auth'), 2);
    });

    test('sin Retry-After hace backoff exponencial creciente', () async {
      final fake = FakeXtreamTransport()
        ..enqueue('auth', rawResponse([], statusCode: 429))
        ..enqueue('auth', rawResponse([], statusCode: 429))
        ..enqueue('auth', jsonResponse({'user_info': null}));

      final waits = <Duration>[];
      final retrying = RetryingXtreamTransport(
        fake,
        baseDelay: const Duration(milliseconds: 100),
        sleep: (d) async {
          waits.add(d);
        },
      );

      final response = await retrying.get(Uri.parse('http://h/player_api.php?action=auth'));

      expect(response.statusCode, 200);
      expect(waits, [
        const Duration(milliseconds: 100),
        const Duration(milliseconds: 200),
      ]);
    });

    test('agota maxRetries y devuelve el último 429 sin lanzar', () async {
      final fake = FakeXtreamTransport()
        ..enqueue('auth', rawResponse([], statusCode: 429))
        ..enqueue('auth', rawResponse([], statusCode: 429));

      final retrying = RetryingXtreamTransport(
        fake,
        maxRetries: 1,
        sleep: (_) async {},
      );

      final response = await retrying.get(Uri.parse('http://h/player_api.php?action=auth'));

      expect(response.statusCode, 429);
      expect(fake.callCount('auth'), 2); // intento original + 1 reintento
    });

    test('una respuesta 200 no dispara ningún reintento', () async {
      final fake = FakeXtreamTransport();
      var slept = false;
      final retrying = RetryingXtreamTransport(
        fake,
        sleep: (_) async => slept = true,
      );

      final response = await retrying.get(Uri.parse('http://h/player_api.php?action=auth'));

      expect(response.statusCode, 200);
      expect(slept, isFalse);
    });
  });
}
