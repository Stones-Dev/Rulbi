import 'dart:convert';
import 'dart:io';

import 'package:iptv_protocols/src/xtream/xtream_transport.dart';

/// Doble de test de [XtreamTransport]: sirve los fixtures desde disco (los
/// 9 dumps reales de T1.1 en `test/fixtures/xtream/dialect_o0zz/`, los
/// sintéticos de `test/fixtures/xtream/synthetic/`) o respuestas
/// preprogramadas, sin tocar la red en ningún test. Enruta por el
/// parámetro `action` de la query string de la URL, igual que hace un
/// panel Xtream real con `player_api.php?action=...`.
final class FakeXtreamTransport implements XtreamTransport {
  FakeXtreamTransport({
    Map<String, String>? actionToFixture,
    Map<String, XtreamHttpResponse>? actionToResponse,
    this.fixturesDir = 'test/fixtures/xtream/dialect_o0zz',
  }) : _actionToFixture = actionToFixture ?? const {},
       _actionToResponse = actionToResponse ?? const {};

  final Map<String, String> _actionToFixture;
  final Map<String, XtreamHttpResponse> _actionToResponse;
  final String fixturesDir;

  /// Cola de respuestas por acción, consumidas en orden (una lista con un
  /// solo elemento se repite indefinidamente) — usada por los tests de
  /// backoff que necesitan un 429 seguido de un 200 real.
  final Map<String, List<XtreamHttpResponse>> _queues = {};

  void enqueue(String action, XtreamHttpResponse response) {
    _queues.putIfAbsent(action, () => []).add(response);
  }

  int callCount(String action) => _calls[action] ?? 0;
  final Map<String, int> _calls = {};

  @override
  Future<XtreamHttpResponse> get(Uri url) async {
    final action = url.queryParameters['action'] ?? 'auth';
    _calls[action] = (_calls[action] ?? 0) + 1;

    final queued = _queues[action];
    if (queued != null && queued.isNotEmpty) {
      return queued.length == 1 ? queued.first : queued.removeAt(0);
    }

    final direct = _actionToResponse[action];
    if (direct != null) return direct;

    final fixtureName = _actionToFixture[action] ?? '$action.json';
    final file = File('$fixturesDir/$fixtureName');
    if (!file.existsSync()) {
      throw StateError(
        'FakeXtreamTransport: no hay fixture ni respuesta programada '
        'para action="$action" (buscado en ${file.path}).',
      );
    }
    return XtreamHttpResponse(
      statusCode: 200,
      bodyBytes: file.readAsBytesSync(),
      contentType: 'application/json',
    );
  }
}

/// Atajo para construir una respuesta JSON 200 a partir de un [Object]
/// codificable (`Map`/`List`), usado por los tests de dialectos sintéticos
/// que arman el JSON inline en vez de leerlo de un fixture.
XtreamHttpResponse jsonResponse(Object? body, {int statusCode = 200}) =>
    XtreamHttpResponse(
      statusCode: statusCode,
      bodyBytes: utf8.encode(jsonEncode(body)),
      contentType: 'application/json',
    );

/// Atajo para una respuesta con cuerpo crudo (HTML de error, texto
/// truncado, bytes Latin-1) — los tests de errores no siempre parten de
/// JSON válido.
XtreamHttpResponse rawResponse(
  List<int> bodyBytes, {
  int statusCode = 200,
  String? contentType,
  Duration? retryAfter,
}) => XtreamHttpResponse(
  statusCode: statusCode,
  bodyBytes: bodyBytes,
  contentType: contentType,
  retryAfter: retryAfter,
);
