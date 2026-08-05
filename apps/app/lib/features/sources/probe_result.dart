/// Resultado tipado del botón "Probar"/"Probar conexión" (ui-spec §2.8/
/// §2.9, S4 · Ola 2). Cada formulario tiene su propio tipo de éxito
/// ([M3uProbeSummary]/`XtreamProbeSummary`), pero comparten la forma de
/// fallo: un probe nunca construye una cadena de usuario directamente —
/// devuelve un [ProbeFailureReason] tipado, y es el widget quien lo
/// traduce vía `AppLocalizations` (P7: sin excepciones, todas las cadenas
/// nuevas nacen i18n-ready).
library;

sealed class ProbeResult<T> {
  const ProbeResult();
}

final class ProbeOk<T> extends ProbeResult<T> {
  const ProbeOk(this.value);
  final T value;
}

final class ProbeFailed<T> extends ProbeResult<T> {
  const ProbeFailed(this.reason);
  final ProbeFailureReason reason;
}

/// Catálogo de motivos de fallo compartido entre el probe M3U y el probe
/// Xtream — no todos los valores aplican a ambos (p. ej. `authFailed` solo
/// lo produce Xtream), pero un catálogo único simplifica el widget
/// compartido que renderiza el banner de resultado
/// (`source_form_widgets.dart`).
enum ProbeFailureReason {
  network,
  timeout,
  notFound,
  malformed,
  authFailed,
  accountExpired,
  accountDisabled,
  rateLimited,
  unknown,
}
