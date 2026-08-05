import 'dart:convert';

import 'package:iptv_app/features/sources/probe_result.dart';
import 'package:iptv_app/features/sources/xtream_probe.dart';
import 'package:iptv_protocols/iptv_protocols.dart';
import 'package:test/test.dart';

/// S4 · Ola 2 (Formulario Xtream, ui-spec §2.9). `XtreamTransport` falso
/// (mismo puerto que testea `packages/protocols`): sin red real.
void main() {
  group('XtreamClientProbe.probe', () {
    test('cuenta activa: XtreamProbeSummary con estado y nº de streams', () async {
      final transport = _ScriptedXtreamTransport(
        responsesByAction: {
          null: _jsonResponse({
            'user_info': {
              'auth': 1,
              'username': 'demo',
              'status': 'Active',
              'is_trial': '0',
              'active_cons': '1',
              'max_connections': '2',
              'exp_date': '${DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch ~/ 1000}',
            },
          }),
          'get_live_streams': _jsonResponse([
            {'stream_id': 1, 'name': 'Ch1'},
            {'stream_id': 2, 'name': 'Ch2'},
            {'stream_id': 3, 'name': 'Ch3'},
          ]),
        },
      );
      final probe = XtreamClientProbe(transportFactory: () => transport);

      final result = await probe.probe(
        host: Uri.parse('http://panel.example:8080'),
        username: 'demo',
        password: 'secreto',
      );

      expect(result, isA<ProbeOk<XtreamProbeSummary>>());
      final summary = (result as ProbeOk<XtreamProbeSummary>).value;
      expect(summary.account.status, 'Active');
      expect(summary.liveStreamCount, 3);
    });

    test(
      'autenticación ok pero get_live_streams falla: liveStreamCount null, no degrada a fallo',
      () async {
        final transport = _ScriptedXtreamTransport(
          responsesByAction: {
            null: _jsonResponse({
              'user_info': {
                'auth': 1,
                'username': 'demo',
                'status': 'Active',
                'is_trial': '0',
                'active_cons': '1',
                'max_connections': '2',
              },
            }),
            'get_live_streams': const XtreamHttpResponse(
              statusCode: 500,
              bodyBytes: [],
            ),
          },
        );
        final probe = XtreamClientProbe(transportFactory: () => transport);

        final result = await probe.probe(
          host: Uri.parse('http://panel.example:8080'),
          username: 'demo',
          password: 'secreto',
        );

        final summary = (result as ProbeOk<XtreamProbeSummary>).value;
        expect(summary.liveStreamCount, isNull);
      },
    );

    test('auth: 0 → ProbeFailureReason.authFailed', () async {
      final transport = _ScriptedXtreamTransport(
        responsesByAction: {
          null: _jsonResponse({
            'user_info': {'auth': 0},
          }),
        },
      );
      final probe = XtreamClientProbe(transportFactory: () => transport);

      final result = await probe.probe(
        host: Uri.parse('http://panel.example:8080'),
        username: 'demo',
        password: 'incorrecta',
      );

      expect(
        (result as ProbeFailed<XtreamProbeSummary>).reason,
        ProbeFailureReason.authFailed,
      );
    });

    test('cuenta expirada → ProbeFailureReason.accountExpired', () async {
      final transport = _ScriptedXtreamTransport(
        responsesByAction: {
          null: _jsonResponse({
            'user_info': {
              'auth': 1,
              'username': 'demo',
              'status': 'Expired',
              'is_trial': '0',
              'active_cons': '0',
              'max_connections': '1',
            },
          }),
        },
      );
      final probe = XtreamClientProbe(transportFactory: () => transport);

      final result = await probe.probe(
        host: Uri.parse('http://panel.example:8080'),
        username: 'demo',
        password: 'secreto',
      );

      expect(
        (result as ProbeFailed<XtreamProbeSummary>).reason,
        ProbeFailureReason.accountExpired,
      );
    });

    test('429 sin reintentos configurados → ProbeFailureReason.rateLimited', () async {
      final transport = _ScriptedXtreamTransport(
        responsesByAction: {
          null: const XtreamHttpResponse(statusCode: 429, bodyBytes: []),
        },
      );
      final probe = XtreamClientProbe(transportFactory: () => transport);

      final result = await probe.probe(
        host: Uri.parse('http://panel.example:8080'),
        username: 'demo',
        password: 'secreto',
      );

      expect(
        (result as ProbeFailed<XtreamProbeSummary>).reason,
        ProbeFailureReason.rateLimited,
      );
    });
  });
}

XtreamHttpResponse _jsonResponse(Object? body) => XtreamHttpResponse(
  statusCode: 200,
  bodyBytes: utf8.encode(jsonEncode(body)),
  contentType: 'application/json',
);

/// Doble de [XtreamTransport] indexado por `action` (query param), no por
/// URL completa — evita acoplar el test a la forma exacta de
/// `_playerApiUrl` (host/orden de query params).
final class _ScriptedXtreamTransport implements XtreamTransport {
  _ScriptedXtreamTransport({required this.responsesByAction});

  final Map<String?, XtreamHttpResponse> responsesByAction;

  @override
  Future<XtreamHttpResponse> get(Uri url) async {
    final action = url.queryParameters['action'];
    final response = responsesByAction[action];
    if (response == null) {
      throw StateError('Sin respuesta configurada para action="$action" ($url)');
    }
    return response;
  }
}
