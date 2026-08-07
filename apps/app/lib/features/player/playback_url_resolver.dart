import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_protocols/iptv_protocols.dart';

/// Materializa la URL reproducible de un [Channel] (S6, Bloque B) —
/// mismo criterio que [XtreamEpgFallback] (S5.5, Bloque A3): compone los
/// tres puertos que hace falta tener a la vez (`SourceRepository`,
/// `SecureCredentialStore`, y aquí `XtreamUrlResolver` de `protocols`), así
/// que vive en `apps/app`, no en `core` ni en `protocols` (ninguno de los
/// dos conoce a los otros dos a la vez).
///
/// `Channel.url` de una fuente Xtream es **canónica**, sin secretos
/// (`xtream://<sourceId>/<kind>/<id>[.ext]`, ADR-006) — nunca reproducible
/// directamente. Una fuente M3U, en cambio, ya trae la URL `http(s)` real
/// desde el import: no hay nada que resolver.
final class PlaybackUrlResolver {
  PlaybackUrlResolver({required this._sources, required this._secureStore});

  final SourceRepository _sources;
  final SecureCredentialStore _secureStore;

  /// `null` = no reproducible: el secreto no está guardado, la fuente ya
  /// no existe, o [channel] es una serie del catálogo
  /// (`xtream://.../series-catalog/...`, S5.5 Bloque C) — una serie se
  /// abre, no se reproduce (mismo criterio que
  /// `XtreamUrlResolver.seriesCatalogCanonical`, que rechaza ese `kind` en
  /// `resolve`).
  Future<Uri?> resolve(Channel channel) async {
    final canonical = channel.url;
    if (canonical.scheme != 'xtream') return canonical;

    // `series-catalog` no tiene forma reproducible — `XtreamUrlResolver
    // .resolve` lo rechazaría con ArgumentError; se detecta antes de
    // llamarlo para devolver "no reproducible" en vez de lanzar.
    final kind = canonical.pathSegments.isNotEmpty ? canonical.pathSegments.first : null;
    if (kind == 'series-catalog') return null;

    final source = await _sources.getById(channel.sourceId);
    final config = source?.config;
    if (config is! XtreamSourceConfig) return null;

    final secret = await _secureStore.read(channel.sourceId);
    if (secret == null) return null;

    return XtreamUrlResolver.resolve(
      canonical: canonical,
      panelHost: config.host,
      username: config.username,
      secret: secret,
    );
  }
}
