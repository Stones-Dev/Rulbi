/// Normalización de la "URL del servidor" del formulario Xtream
/// (ui-spec §2.9), S4 · Ola 2. ADR-006 fija que el conocimiento de la
/// forma de URL de un panel Xtream vive en un solo sitio de
/// `packages/protocols` — este archivo es esa pieza para la entrada del
/// usuario, complementaria a `xtream_url_resolver.dart` (que resuelve la
/// URL reproducible en el momento de reproducir).
///
/// El usuario puede teclear cualquier variante razonable
/// (`host:puerto`, `http://host/`, o incluso pegar la URL completa que le
/// dio su proveedor con `player_api.php` y las credenciales como query) —
/// esta función la reduce a la forma canónica que espera
/// `XtreamClient.host`/`XtreamSourceConfig.host`: esquema http(s), sin
/// `player_api.php`, sin query ni fragment, sin barra final.
library;

/// Resultado de [normalizeXtreamPanelHost].
sealed class XtreamHostResult {
  const XtreamHostResult();
}

final class XtreamHostOk extends XtreamHostResult {
  const XtreamHostOk(this.host);
  final Uri host;
}

/// Motivo de rechazo. `embeddedCredentials` es el caso de seguridad
/// (P5/ADR-006): la URL del panel nunca lleva usuario/contraseña — esos
/// campos son independientes en el formulario y viajan al almacén seguro,
/// nunca a `Source.config`.
enum XtreamHostInvalidReason { empty, malformed, embeddedCredentials }

final class XtreamHostInvalid extends XtreamHostResult {
  const XtreamHostInvalid(this.reason);
  final XtreamHostInvalidReason reason;
}

XtreamHostResult normalizeXtreamPanelHost(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    return const XtreamHostInvalid(XtreamHostInvalidReason.empty);
  }

  final withScheme = trimmed.contains('://') ? trimmed : 'http://$trimmed';
  final uri = Uri.tryParse(withScheme);
  if (uri == null ||
      uri.host.isEmpty ||
      (uri.scheme != 'http' && uri.scheme != 'https')) {
    return const XtreamHostInvalid(XtreamHostInvalidReason.malformed);
  }

  if (uri.userInfo.isNotEmpty) {
    return const XtreamHostInvalid(XtreamHostInvalidReason.embeddedCredentials);
  }

  var segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.isNotEmpty && segments.last.toLowerCase() == 'player_api.php') {
    segments = segments.sublist(0, segments.length - 1);
  }

  return XtreamHostOk(
    Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      pathSegments: segments,
    ),
  );
}
