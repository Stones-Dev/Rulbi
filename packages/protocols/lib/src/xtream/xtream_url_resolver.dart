/// Construcción y resolución de URLs Xtream sin filtrar credenciales
/// (ADR-006, T1.4). La URL reproducible de un panel Xtream real es
/// `http://host:port/live/USUARIO/CONTRASEÑA/123.ts` — si eso fuera a
/// `Channel.url` directamente, la contraseña acabaría en texto plano en
/// la tabla `channels`, en `ChannelRef` (cuya cascada es
/// tvg-id → url → nombre) y por tanto en el paquete de `pairing` que
/// viaja por la red (P5, y contra el propio `XtreamSourceConfig`, que ya
/// declara que nunca lleva la contraseña).
///
/// Se resuelve con dos formas de URL:
/// - **Canónica** (`xtream://<sourceId>/<kind>/<id>`): sin secretos, es lo
///   que vive en `Channel.url` y en el argumento `url` de
///   `ChannelRef.derive`. Estable frente a un refresco del panel.
/// - **Reproducible**: se materializa combinando la canónica con
///   host/usuario/secreto justo en el momento de reproducir —
///   responsabilidad de `packages/player` (F2), no de este cliente. El
///   conocimiento de la forma de URL de un panel Xtream vive en un solo
///   sitio (aquí) para que ni `core` ni `player` tengan que reinventarlo.
library;

/// `live`: sin extensión — `ts` vs `m3u8` es preferencia de la *fuente*
/// (ver `XtreamAccount.allowedOutputFormats`), no una propiedad del
/// canal, y no debe formar parte de su identidad estable.
///
/// `movie`/`series`: **dos** variantes.
/// [movieCanonical]/[seriesCanonical] llevan la extensión real
/// (`container_extension`) — es lo que va a `Channel.url`, porque ahí sí
/// hace falta para reproducir. [movieRefCanonical]/[seriesRefCanonical]
/// son la misma ruta **sin** extensión, y son las que alimentan
/// `ChannelRef.derive` cuando no hay `tvg-id`: un panel que reetiqueta
/// `mkv`→`mp4` en un refresco no debe romper los favoritos del usuario
/// (mismo criterio que ya aplica `live`, extendido a VOD/series).
final class XtreamUrlResolver {
  const XtreamUrlResolver._();

  static Uri liveCanonical({required String sourceId, required String streamId}) =>
      _canonical(sourceId, 'live', streamId);

  static Uri movieCanonical({
    required String sourceId,
    required String streamId,
    String? containerExtension,
  }) => _canonical(sourceId, 'movie', streamId, extension: containerExtension);

  static Uri movieRefCanonical({required String sourceId, required String streamId}) =>
      _canonical(sourceId, 'movie', streamId);

  static Uri seriesCanonical({
    required String sourceId,
    required String episodeId,
    String? containerExtension,
  }) => _canonical(sourceId, 'series', episodeId, extension: containerExtension);

  static Uri seriesRefCanonical({required String sourceId, required String episodeId}) =>
      _canonical(sourceId, 'series', episodeId);

  static Uri _canonical(String sourceId, String kind, String id, {String? extension}) {
    final hasExt = extension != null && extension.trim().isNotEmpty;
    final idWithExt = hasExt ? '$id.${extension.trim()}' : id;
    return Uri(scheme: 'xtream', host: sourceId, pathSegments: [kind, idWithExt]);
  }

  /// Combina una URL canónica (sin secretos) con el host del panel y las
  /// credenciales reales para obtener la URL reproducible. La contraseña
  /// entra aquí y solo aquí, en el momento de reproducir — nunca antes,
  /// nunca persistida (P5). El llamador la obtiene de
  /// `SecureCredentialStore` justo antes de llamar a esta función.
  ///
  /// Usa `Uri(pathSegments: ...)` (no interpolación de string) a
  /// propósito: si algún día una contraseña contuviera `/` u otro
  /// carácter reservado, `pathSegments` lo percent-encoda correctamente
  /// en vez de partir la ruta en un segmento de más.
  static Uri resolve({
    required Uri canonical,
    required Uri panelHost,
    required String username,
    required String secret,
    String liveOutputFormat = 'ts',
  }) {
    if (canonical.scheme != 'xtream') {
      throw ArgumentError.value(canonical, 'canonical', 'no es una URL canónica xtream://');
    }
    final segments = canonical.pathSegments;
    if (segments.length != 2) {
      throw ArgumentError.value(
        canonical,
        'canonical',
        'forma inesperada, se esperaba xtream://<sourceId>/<kind>/<id>[.ext]',
      );
    }
    final kind = segments[0];
    final idAndExt = segments[1];

    final String lastSegment;
    switch (kind) {
      case 'live':
        lastSegment = '$idAndExt.$liveOutputFormat';
      case 'movie':
      case 'series':
        lastSegment = idAndExt; // ya trae su extensión, si la había.
      default:
        throw ArgumentError.value(canonical, 'canonical', 'tipo de contenido Xtream desconocido: "$kind"');
    }

    return Uri(
      scheme: panelHost.scheme.isEmpty ? 'http' : panelHost.scheme,
      host: panelHost.host,
      port: panelHost.hasPort ? panelHost.port : null,
      pathSegments: [
        ...panelHost.pathSegments.where((s) => s.isNotEmpty),
        kind,
        username,
        secret,
        lastSegment,
      ],
    );
  }

  /// URL de la guía XMLTV que sirve el propio panel (`xmltv.php`, S5.5
  /// Bloque A) — transporte principal de EPG Xtream: una sola descarga en
  /// vez de una petición `get_short_epg`/`get_simple_data_table` por canal
  /// (ver `xtream_epg.dart`, que queda como fallback bajo demanda). A
  /// diferencia de [resolve], esta URL sí es la que se descarga
  /// directamente (nunca se persiste — `EpgSource.epgFor` la construye y
  /// la descarga en el momento, igual que ya hace con la guía M3U por
  /// URL), así que usa `queryParameters` (no `pathSegments`) para que el
  /// propio `Uri` percent-encode la contraseña sin que el llamador tenga
  /// que pensarlo.
  static Uri xmltvUrl({required Uri panelHost, required String username, required String secret}) {
    return Uri(
      scheme: panelHost.scheme.isEmpty ? 'http' : panelHost.scheme,
      host: panelHost.host,
      port: panelHost.hasPort ? panelHost.port : null,
      pathSegments: [...panelHost.pathSegments.where((s) => s.isNotEmpty), 'xmltv.php'],
      queryParameters: {'username': username, 'password': secret},
    );
  }
}
