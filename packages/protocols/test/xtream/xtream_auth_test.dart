import 'package:iptv_protocols/src/xtream/xtream_client.dart';
import 'package:iptv_protocols/src/xtream/xtream_failure.dart';
import 'package:test/test.dart';

import 'support/fake_xtream_transport.dart';

/// T1.4: auth es la primera acción de cualquier cliente Xtream real —
/// "Autenticación: username+password en la URL, respuesta con user_info
/// (estado, expiración) y server_info. Manejar auth failed como error
/// tipado, no como excepción" (encargo original).
void main() {
  group('XtreamClient.authenticate', () {
    test('fixture real (o0Zz/xtreamcodeserver): cuenta activa sin expiración', () async {
      final client = _client(FakeXtreamTransport());

      final result = await client.authenticate();

      expect(result, isA<XtreamOk<Object?>>());
      final account = (result as XtreamOk).value;
      expect(account.username, 'test');
      expect(account.status, 'Active');
      expect(account.isTrial, isFalse);
      expect(account.maxConnections, 1);
      expect(account.expiresAt, isNull, reason: 'auth.json real no trae exp_date');
      expect(account.allowedOutputFormats, ['m3u8', 'ts']);
    });

    test('auth: 0 -> XtreamAuthFailed', () async {
      final fake = FakeXtreamTransport()
        ..enqueue('auth', jsonResponse({'user_info': {'auth': 0, 'status': 'Active'}}));
      final client = _client(fake);

      final result = await client.authenticate();

      expect(result, isA<XtreamErr<Object?>>());
      expect((result as XtreamErr).failure, isA<XtreamAuthFailed>());
    });

    test('user_info ausente -> XtreamAuthFailed (credenciales rechazadas)', () async {
      final fake = FakeXtreamTransport()..enqueue('auth', jsonResponse({}));
      final client = _client(fake);

      final result = await client.authenticate();

      expect((result as XtreamErr).failure, isA<XtreamAuthFailed>());
    });

    test('status Expired con exp_date pasado -> XtreamAccountExpired', () async {
      final fake = FakeXtreamTransport()
        ..enqueue(
          'auth',
          jsonResponse({
            'user_info': {'auth': 1, 'status': 'Expired', 'exp_date': '946684800'}, // 2000-01-01
          }),
        );
      final client = _client(fake);

      final result = await client.authenticate();

      final failure = (result as XtreamErr).failure as XtreamAccountExpired;
      expect(failure.expiresAt, DateTime.utc(2000));
    });

    test('auth:1 pero fecha de expiración ya pasada -> XtreamAccountExpired aunque status no lo diga', () async {
      final fake = FakeXtreamTransport()
        ..enqueue(
          'auth',
          jsonResponse({
            'user_info': {'auth': 1, 'status': 'Active', 'exp_date': 946684800},
          }),
        );
      final client = _client(fake);

      final result = await client.authenticate();

      expect((result as XtreamErr).failure, isA<XtreamAccountExpired>());
    });

    for (final status in ['Banned', 'Disabled']) {
      test('status $status -> XtreamAccountDisabled', () async {
        final fake = FakeXtreamTransport()
          ..enqueue('auth', jsonResponse({'user_info': {'auth': 1, 'status': status}}));
        final client = _client(fake);

        final result = await client.authenticate();

        final failure = (result as XtreamErr).failure as XtreamAccountDisabled;
        expect(failure.status, status);
      });
    }

    test('exp_date null -> cuenta sin caducidad, no es un error', () async {
      final fake = FakeXtreamTransport()
        ..enqueue(
          'auth',
          jsonResponse({
            'user_info': {'auth': 1, 'status': 'Active', 'exp_date': null},
          }),
        );
      final client = _client(fake);

      final result = await client.authenticate();

      expect(result, isA<XtreamOk<Object?>>());
      expect((result as XtreamOk).value.expiresAt, isNull);
    });

    test('exp_date como string vacía se trata igual que ausente', () async {
      final fake = FakeXtreamTransport()
        ..enqueue(
          'auth',
          jsonResponse({
            'user_info': {'auth': 1, 'status': 'Active', 'exp_date': ''},
          }),
        );
      final client = _client(fake);

      final result = await client.authenticate();

      expect((result as XtreamOk).value.expiresAt, isNull);
    });
  });
}

XtreamClient _client(FakeXtreamTransport transport) => XtreamClient(
  host: Uri.parse('http://127.0.0.1:8081'),
  username: 'test',
  password: 'test',
  transport: transport,
);
