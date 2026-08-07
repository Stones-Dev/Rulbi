import 'package:http/http.dart' as http;
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_protocols/iptv_protocols.dart';

/// Puerto que produce el `XmltvParseOutcome` de la guía de una fuente, si
/// tiene una (S5 · Ola 2, ADR-008; S5.5 Bloque A2 añade Xtream) — análogo
/// exacto a `ImportChannelSource` (`import_controller.dart`): una interfaz
/// fina que [ImportController] puede fakear en sus tests sin red ni
/// isolates reales.
///
/// Reutiliza `XmltvParseOutcome` (`packages/protocols`) tal cual en vez de
/// envolverlo en un tipo propio — ya trae exactamente lo que hace falta
/// (`entries`/`report`), y `parseXmltv` no necesita adaptación (P6).
abstract interface class EpgSource {
  /// `null` si [source] no tiene guía configurada (`epgUrl` ausente en
  /// M3U). Una fuente Xtream siempre devuelve no-`null` — su guía es
  /// `xmltv.php`, servido por el propio panel (S5.5) — [ImportController]
  /// solo trata como "sin fase EPG" el caso M3U sin `epgUrl`.
  XmltvParseOutcome? epgFor(Source source, {required DateTime now});
}

/// XMLTV real: descarga por `http` hacia `parseXmltv` (API pública de
/// `packages/protocols`, que ya detecta `.gz` por los bytes mágicos y no
/// necesita ayuda del llamador, ver `xmltv_encoding.dart`). Para M3U, la
/// guía siempre es una URL (tenga la fuente M3U por URL o por fichero
/// local — solo la lista de canales puede ser un fichero). Para Xtream
/// (S5.5, Bloque A), la URL es `xmltv.php` del propio panel
/// (`XtreamUrlResolver.xmltvUrl`) — transporte principal de EPG Xtream, en
/// una sola descarga en vez de una petición por canal (ver
/// `xtreamEpgToEntries`, fallback bajo demanda para cuando un panel no
/// sirve `xmltv.php`).
final class XmltvEpgSource implements EpgSource {
  XmltvEpgSource({required this._secureStore, http.Client? client}) : _client = client ?? http.Client();

  final SecureCredentialStore _secureStore;
  final http.Client _client;

  @override
  XmltvParseOutcome? epgFor(Source source, {required DateTime now}) {
    final window = XmltvWindow.around(now);

    // Ventana por defecto del producto (`now-1d, now+7d`, ver
    // `XmltvWindow.around`) — la misma que usa la purga por ventana
    // (`RunPurgePolicy`), así que lo que este escritor persiste y lo que
    // la purga conserva son la misma ventana por construcción.
    switch (source.config) {
      case M3uUrlSourceConfig(:final epgUrl, :final userAgent):
        if (epgUrl == null) return null;
        return parseXmltv(bytes: _fetchUrl(epgUrl, userAgent), window: window);
      case M3uFileSourceConfig(:final epgUrl):
        if (epgUrl == null) return null;
        return parseXmltv(bytes: _fetchUrl(epgUrl, null), window: window);
      case XtreamSourceConfig(:final host, :final username):
        return parseXmltv(
          bytes: _fetchXtreamXmltv(sourceId: source.id, host: host, username: username),
          window: window,
        );
    }
  }

  /// La credencial se lee **dentro** del generador, no en [epgFor] — así
  /// [epgFor] sigue siendo síncrono y el puerto no cambia de firma. Esto
  /// también conserva el `onListen` diferido de `parseXmltv`: sin
  /// escucha de `.entries`, nunca se toca `SecureCredentialStore` ni se
  /// hace ninguna petición. Sin credencial guardada, se lanza dentro del
  /// stream — `ImportController._runEpgPhase` ya lo trata como cualquier
  /// otro fallo de guía (`ProbeFailureReason`, nunca `ImportFailed`).
  Stream<List<int>> _fetchXtreamXmltv({
    required String sourceId,
    required Uri host,
    required String username,
  }) async* {
    final secret = await _secureStore.read(sourceId);
    if (secret == null) {
      throw StateError('Sin credencial guardada para la fuente Xtream "$sourceId".');
    }
    final url = XtreamUrlResolver.xmltvUrl(panelHost: host, username: username, secret: secret);
    yield* _fetchUrl(url, null);
  }

  Stream<List<int>> _fetchUrl(Uri url, String? userAgent) async* {
    final request = http.Request('GET', url);
    if (userAgent != null && userAgent.trim().isNotEmpty) {
      request.headers['User-Agent'] = userAgent.trim();
    }
    final streamed = await _client.send(request);
    if (streamed.statusCode >= 400) {
      throw http.ClientException('HTTP ${streamed.statusCode}', url);
    }
    yield* streamed.stream;
  }
}
