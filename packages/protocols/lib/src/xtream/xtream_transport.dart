import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Puerto de red del cliente Xtream (T1.4). `packages/protocols` no tenía
/// ninguna dependencia de red antes de esta tarea — los parsers M3U/XMLTV
/// reciben `Stream<List<int>>` ya en memoria/disco. El cliente Xtream sí
/// necesita hacer GETs, así que la red entra por un puerto testeable, no
/// por una llamada directa a `http`/`dio`: los tests (incluidos los de
/// dialectos y errores) sirven fixtures desde disco vía [XtreamTransport],
/// sin tocar la red nunca.
abstract interface class XtreamTransport {
  Future<XtreamHttpResponse> get(Uri url);
}

/// Respuesta cruda de una petición Xtream. `bodyBytes` (no `body`) porque
/// el encoding real puede no ser UTF-8 (ver `xtream_errors_test.dart`,
/// cuerpos Latin-1/BOM) — decidir el encoding es responsabilidad de quien
/// interpreta la respuesta (`XtreamClient`), no del transporte.
final class XtreamHttpResponse {
  const XtreamHttpResponse({
    required this.statusCode,
    required this.bodyBytes,
    this.contentType,
    this.retryAfter,
  });

  final int statusCode;
  final List<int> bodyBytes;
  final String? contentType;

  /// `Retry-After` de un 429, si el servidor lo envió (segundos o fecha
  /// HTTP — ya resuelto a [Duration] por quien construye la respuesta).
  final Duration? retryAfter;

  /// Decodifica el cuerpo como texto, con el mismo criterio de
  /// tolerancia que el resto del paquete: intenta UTF-8 estricto y cae a
  /// Latin-1 si falla, en vez de lanzar. Un cuerpo así decodificado puede
  /// no ser JSON válido — eso lo determina quien lo parsea, no aquí.
  String get bodyAsText {
    try {
      return utf8.decode(bodyBytes);
    } on FormatException {
      return latin1.decode(bodyBytes);
    }
  }
}

/// Implementación por defecto sobre `package:http` (BSD-3, Dart puro).
/// Un `Client` inyectable de fábrica evita reabrir una conexión por
/// petición y permite a los tests de integración real (no incluidos en la
/// batería offline de esta tarea) sustituirlo.
final class HttpXtreamTransport implements XtreamTransport {
  HttpXtreamTransport({http.Client? client, this.timeout = const Duration(seconds: 15)})
    : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;

  @override
  Future<XtreamHttpResponse> get(Uri url) async {
    final http.Response response;
    try {
      response = await _client.get(url).timeout(timeout);
    } on TimeoutException {
      rethrow;
    } on SocketException {
      rethrow;
    }

    return XtreamHttpResponse(
      statusCode: response.statusCode,
      bodyBytes: response.bodyBytes,
      contentType: response.headers['content-type'],
      retryAfter: _parseRetryAfter(response.headers['retry-after']),
    );
  }

  static Duration? _parseRetryAfter(String? header) {
    if (header == null || header.trim().isEmpty) return null;
    final seconds = int.tryParse(header.trim());
    if (seconds != null) return Duration(seconds: seconds.clamp(0, 3600));
    // `HttpDate.parse` (dart:io) no tiene variante `tryParse` — la forma
    // HTTP-date de `Retry-After` es rara en la práctica (casi todos los
    // paneles mandan segundos), así que se tolera con try/catch en vez de
    // reimplementar el parseo de RFC 7231.
    try {
      final date = HttpDate.parse(header);
      final diff = date.difference(DateTime.now());
      return diff.isNegative ? Duration.zero : diff;
    } on FormatException {
      return null;
    }
  }
}

/// Decorador de backoff/rate-limiting (P4 del encargo de T1.4: algunos
/// paneles limitan agresivamente). Envuelve cualquier [XtreamTransport] —
/// en producción, [HttpXtreamTransport]; en test, [FakeXtreamTransport]
/// configurado para devolver 429 antes de un fixture real. Toma un reloj y
/// una función de espera inyectables para que los tests de backoff no
/// dependan de dormir de verdad ni de la red (ver `xtream_errors_test.dart`).
final class RetryingXtreamTransport implements XtreamTransport {
  RetryingXtreamTransport(
    this._inner, {
    this.maxRetries = 3,
    this.baseDelay = const Duration(milliseconds: 500),
    Future<void> Function(Duration)? sleep,
  }) : _sleep = sleep ?? Future<void>.delayed;

  final XtreamTransport _inner;
  final int maxRetries;
  final Duration baseDelay;
  final Future<void> Function(Duration) _sleep;

  @override
  Future<XtreamHttpResponse> get(Uri url) async {
    var attempt = 0;
    while (true) {
      final response = await _inner.get(url);
      if (response.statusCode != 429 || attempt >= maxRetries) return response;

      final wait = response.retryAfter ?? _exponentialBackoff(attempt);
      await _sleep(wait);
      attempt++;
    }
  }

  /// `baseDelay * 2^intento`, sin jitter aleatorio (mantiene el backoff
  /// determinista y testeable sin inyectar una fuente de aleatoriedad
  /// extra) — el jitter real de producción lo introduce la variación
  /// natural de latencia entre reintentos.
  Duration _exponentialBackoff(int attempt) =>
      baseDelay * (1 << attempt.clamp(0, 10));
}
