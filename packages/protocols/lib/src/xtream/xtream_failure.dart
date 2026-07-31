/// Resultado de una llamada Xtream: nunca se lanza una excepción por un
/// panel que responde mal (P7, extendido de M3U/XMLTV a un cliente HTTP) —
/// se tipa el fallo y el llamador decide. `sealed`: el `switch` sobre
/// [XtreamResult] es exhaustivo en compilación, mismo espíritu que
/// `SourceConfig` en `core`.
sealed class XtreamResult<T> {
  const XtreamResult();
}

final class XtreamOk<T> extends XtreamResult<T> {
  const XtreamOk(this.value);
  final T value;
}

final class XtreamErr<T> extends XtreamResult<T> {
  const XtreamErr(this.failure);
  final XtreamFailure failure;
}

/// Catálogo de formas en que una llamada a `player_api.php` puede fallar.
/// `sealed` por el mismo motivo que [XtreamResult]. Ninguna variante lleva
/// la contraseña del usuario ni la URL completa de la petición (que la
/// contendría como query param) — solo datos ya saneados (P5).
sealed class XtreamFailure {
  const XtreamFailure();
}

/// `auth: 0` en la respuesta, o `user_info` ausente. `message` es el que
/// trae el propio panel, si trae alguno.
final class XtreamAuthFailed extends XtreamFailure {
  const XtreamAuthFailed({this.message});
  final String? message;

  @override
  String toString() => 'XtreamAuthFailed(${message ?? "sin mensaje"})';
}

/// `status` distinto de `Active`/`Trial` con fecha de expiración pasada,
/// o cualquier `status` que el panel marque como caducado.
final class XtreamAccountExpired extends XtreamFailure {
  const XtreamAccountExpired({this.expiresAt});
  final DateTime? expiresAt;

  @override
  String toString() => 'XtreamAccountExpired(expiresAt: $expiresAt)';
}

/// `status` en {`Banned`, `Disabled`, ...} — no es un problema de
/// caducidad, es una cuenta que el panel ha desactivado activamente.
final class XtreamAccountDisabled extends XtreamFailure {
  const XtreamAccountDisabled(this.status);
  final String status;

  @override
  String toString() => 'XtreamAccountDisabled($status)';
}

/// HTTP 429 que superó los reintentos de `RetryingXtreamTransport` (o que
/// llegó sin pasar por él).
final class XtreamRateLimited extends XtreamFailure {
  const XtreamRateLimited({this.retryAfter});
  final Duration? retryAfter;

  @override
  String toString() => 'XtreamRateLimited(retryAfter: $retryAfter)';
}

/// Cualquier código HTTP de error que no sea 429 (401/403/500/502/503...).
final class XtreamHttpFailure extends XtreamFailure {
  const XtreamHttpFailure(this.statusCode);
  final int statusCode;

  @override
  String toString() => 'XtreamHttpFailure($statusCode)';
}

/// Cuerpo que no se pudo interpretar como la respuesta esperada: JSON
/// inválido, HTML de error, tipo inesperado (objeto donde se esperaba
/// lista, etc.). [snippet] va acotado a un tamaño legible y nunca puede
/// contener la URL de la petición (que llevaría username/password como
/// query params) — solo un recorte del *cuerpo* de la respuesta.
final class XtreamMalformed extends XtreamFailure {
  const XtreamMalformed({required this.reason, this.snippet = ''});
  final String reason;
  final String snippet;

  @override
  String toString() => 'XtreamMalformed($reason)';
}

/// Fallo de transporte (timeout, DNS, conexión rechazada) que no llegó a
/// producir una respuesta HTTP.
final class XtreamNetworkFailure extends XtreamFailure {
  const XtreamNetworkFailure(this.reason);
  final String reason;

  @override
  String toString() => 'XtreamNetworkFailure($reason)';
}
