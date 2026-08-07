import 'package:http/http.dart' as http;
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_protocols/iptv_protocols.dart';

/// Puerto que produce el `XmltvParseOutcome` de la guía de una fuente, si
/// tiene una (S5 · Ola 2, ADR-008) — análogo exacto a
/// `ImportChannelSource` (`import_controller.dart`): una interfaz fina que
/// [ImportController] puede fakear en sus tests sin red ni isolates
/// reales.
///
/// Reutiliza `XmltvParseOutcome` (`packages/protocols`) tal cual en vez de
/// envolverlo en un tipo propio — ya trae exactamente lo que hace falta
/// (`entries`/`report`), y `parseXmltv` no necesita adaptación (P6).
abstract interface class EpgSource {
  /// `null` si [source] no tiene guía configurada (`epgUrl` ausente, o la
  /// fuente es Xtream — ADR-008 solo cubre XMLTV, la guía de Xtream queda
  /// fuera de esta ola) — [ImportController] lo trata como "sin fase EPG",
  /// no como un fallo.
  XmltvParseOutcome? epgFor(Source source, {required DateTime now});
}

/// XMLTV real: descarga por `http` (la guía siempre es una URL, tenga la
/// fuente M3U por URL o por fichero local — solo la lista de canales puede
/// ser un fichero) hacia `parseXmltv` (API pública de `packages/protocols`,
/// que ya detecta `.gz` por los bytes mágicos y no necesita ayuda del
/// llamador, ver `xmltv_encoding.dart`).
final class XmltvEpgSource implements EpgSource {
  XmltvEpgSource({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  @override
  XmltvParseOutcome? epgFor(Source source, {required DateTime now}) {
    final (epgUrl, userAgent) = switch (source.config) {
      M3uUrlSourceConfig(:final epgUrl, :final userAgent) => (
        epgUrl,
        userAgent,
      ),
      M3uFileSourceConfig(:final epgUrl) => (epgUrl, null),
      // Fuera de alcance (ADR-008 solo cubre XMLTV, no la guía de Xtream).
      XtreamSourceConfig() => (null, null),
    };
    if (epgUrl == null) return null;

    // Ventana por defecto del producto (`now-1d, now+7d`, ver
    // `XmltvWindow.around`) — la misma que usa la purga por ventana
    // (`RunPurgePolicy`), así que lo que este escritor persiste y lo que
    // la purga conserva son la misma ventana por construcción.
    return parseXmltv(
      bytes: _fetchUrl(epgUrl, userAgent),
      window: XmltvWindow.around(now),
    );
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
