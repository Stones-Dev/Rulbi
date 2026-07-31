import 'dart:convert';

import 'package:iptv_protocols/src/xtream/xtream_client.dart';
import 'package:iptv_protocols/src/xtream/xtream_failure.dart';
import 'package:iptv_protocols/src/xtream/xtream_transport.dart';
import 'package:test/test.dart';

import 'support/fake_xtream_transport.dart';

/// T1.4: "servidores que devuelven HTML de error en lugar de JSON — sí,
/// ocurre" (encargo original). Ninguno de estos casos debe lanzar una
/// excepción al llamador: todos se resuelven a un [XtreamFailure] tipado.
void main() {
  group('XtreamClient — errores de red/HTTP/decodificación', () {
    test('429 sin decorador de reintentos -> XtreamRateLimited', () async {
      final fake = FakeXtreamTransport()
        ..enqueue('auth', rawResponse([], statusCode: 429, retryAfter: const Duration(seconds: 5)));
      final client = _client(fake);

      final result = await client.authenticate();

      final failure = (result as XtreamErr).failure as XtreamRateLimited;
      expect(failure.retryAfter, const Duration(seconds: 5));
    });

    test('500 -> XtreamHttpFailure(500)', () async {
      final fake = FakeXtreamTransport()..enqueue('auth', rawResponse([], statusCode: 500));
      final client = _client(fake);

      final result = await client.authenticate();

      final failure = (result as XtreamErr).failure as XtreamHttpFailure;
      expect(failure.statusCode, 500);
    });

    test('401 -> XtreamHttpFailure(401)', () async {
      final fake = FakeXtreamTransport()..enqueue('auth', rawResponse([], statusCode: 401));
      final client = _client(fake);

      final result = await client.authenticate();

      expect(((result as XtreamErr).failure as XtreamHttpFailure).statusCode, 401);
    });

    test('HTML de error donde se espera JSON (portal cautivo/Cloudflare) -> XtreamMalformed', () async {
      final html = '<html><body>502 Bad Gateway</body></html>';
      final fake = FakeXtreamTransport()
        ..enqueue('auth', rawResponse(utf8.encode(html), contentType: 'text/html; charset=utf-8'));
      final client = _client(fake);

      final result = await client.authenticate();

      final failure = (result as XtreamErr).failure as XtreamMalformed;
      expect(failure.reason, contains('HTML'));
      expect(failure.snippet, contains('502 Bad Gateway'));
    });

    test('HTML sin content-type declarado (detectado por el primer carácter) -> XtreamMalformed', () async {
      final html = '<!DOCTYPE html><html></html>';
      final fake = FakeXtreamTransport()..enqueue('auth', rawResponse(utf8.encode(html)));
      final client = _client(fake);

      final result = await client.authenticate();

      expect((result as XtreamErr).failure, isA<XtreamMalformed>());
    });

    test('JSON truncado a mitad de objeto -> XtreamMalformed, nunca lanza', () async {
      final truncated = '{"user_info": {"auth": 1, "stat';
      final fake = FakeXtreamTransport()..enqueue('auth', rawResponse(utf8.encode(truncated)));
      final client = _client(fake);

      final result = await client.authenticate();

      final failure = (result as XtreamErr).failure as XtreamMalformed;
      expect(failure.reason, contains('JSON inválido'));
    });

    test('[] donde se espera un objeto -> XtreamMalformed', () async {
      final fake = FakeXtreamTransport()..enqueue('auth', jsonResponse([]));
      final client = _client(fake);

      final result = await client.authenticate();

      expect((result as XtreamErr).failure, isA<XtreamMalformed>());
    });

    test('cuerpo vacío -> XtreamMalformed', () async {
      final fake = FakeXtreamTransport()..enqueue('auth', rawResponse([]));
      final client = _client(fake);

      final result = await client.authenticate();

      expect((result as XtreamErr).failure, isA<XtreamMalformed>());
    });

    test('cuerpo Latin-1 con caracteres fuera de rango UTF-8 no lanza al decodificar', () async {
      // 0xE9 = 'é' en Latin-1, inválido como continuación UTF-8 aislada.
      final latin1Body = [
        ...utf8.encode('{"user_info": {"auth": 1, "status": "Activo'),
        0xE9,
        ...utf8.encode('n"}}'),
      ];
      final fake = FakeXtreamTransport()..enqueue('auth', rawResponse(latin1Body));
      final client = _client(fake);

      // No debe lanzar FormatException/excepción de decodificación —
      // XtreamHttpResponse.bodyAsText cae a Latin-1 si UTF-8 estricto
      // falla (mismo criterio que M3U/XMLTV con encodings mixtos).
      final result = await client.authenticate();
      expect(result, isA<XtreamResult<Object?>>());
    });

    test('fallo de transporte (excepción de red) -> XtreamNetworkFailure, nunca se propaga', () async {
      final client = XtreamClient(
        host: Uri.parse('http://127.0.0.1:8081'),
        username: 'test',
        password: 'super-secreta',
        transport: _ThrowingTransport(
          Exception('Connection refused, uri=http://127.0.0.1:8081/player_api.php?username=test&password=super-secreta'),
        ),
      );

      final result = await client.authenticate();

      final failure = (result as XtreamErr).failure as XtreamNetworkFailure;
      expect(
        failure.reason,
        isNot(contains('super-secreta')),
        reason: 'P5: la contraseña nunca debe aparecer en un fallo tipado',
      );
      expect(failure.reason, contains('password=***'));
    });
  });
}

XtreamClient _client(FakeXtreamTransport transport) => XtreamClient(
  host: Uri.parse('http://127.0.0.1:8081'),
  username: 'test',
  password: 'test',
  transport: transport,
);

final class _ThrowingTransport implements XtreamTransport {
  _ThrowingTransport(this._error);
  final Object _error;

  @override
  Future<XtreamHttpResponse> get(Uri url) => Future<XtreamHttpResponse>.error(_error);
}
