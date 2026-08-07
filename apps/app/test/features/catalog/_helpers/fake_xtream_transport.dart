import 'dart:convert';

import 'package:iptv_protocols/iptv_protocols.dart';

/// `XtreamTransport` en memoria, local a las fichas VOD/Serie (S6, Bloque
/// D) — mismo patrón que `_FakeXtreamTransport` de
/// `xtream_epg_fallback_test.dart` (helper interno de ese test, no
/// exportado, así que no se reutiliza tal cual): registra cuántas veces se
/// llamó a cada `action` (clave de la caché de `vodInfoProvider`/
/// `seriesInfoProvider`) y permite fijar cuerpo/estado por acción.
final class FakeXtreamTransport implements XtreamTransport {
  final Map<String, String> _bodyByAction = {};
  final Map<String, int> _statusByAction = {};
  final List<Uri> calls = [];

  void respond(String action, String body) => _bodyByAction[action] = body;

  void respondWithStatus(String action, int statusCode) => _statusByAction[action] = statusCode;

  int callsFor(String action) => calls.where((u) => u.queryParameters['action'] == action).length;

  @override
  Future<XtreamHttpResponse> get(Uri url) async {
    final action = url.queryParameters['action'] ?? '';
    calls.add(url);
    final statusCode = _statusByAction[action] ?? 200;
    final body = _bodyByAction[action] ?? '{}';
    return XtreamHttpResponse(
      statusCode: statusCode,
      bodyBytes: utf8.encode(body),
      contentType: 'application/json',
    );
  }
}
