import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_data/iptv_data.dart';
import 'package:iptv_protocols/iptv_protocols.dart';

/// Fallback bajo demanda de EPG Xtream, por canal (S5.5, Bloque A3) — para
/// cuando el panel no sirve `xmltv.php` (ruta principal, ver `EpgSource`/
/// `XtreamUrlResolver.xmltvUrl`) o su descarga falló, y un canal concreto
/// se queda sin "ahora/siguiente" real. **Nunca en bloque**: cada llamada
/// es una petición `get_simple_data_table` de un único `stream_id` — para
/// N canales harían falta N peticiones, por eso esto no es la ruta de
/// ingesta principal (ver docstring de `xtreamEpgToEntries`).
///
/// No lanza nunca: un fallo aquí ("seguimos sin EPG para este canal") no
/// debe convertirse en un error de la pantalla que lo pidió — mismo
/// criterio que el resto de EPG (P7).
final class XtreamEpgFallback {
  XtreamEpgFallback({
    required this._epgRepository,
    required this._writer,
    required this._sources,
    required this._secureStore,
    XtreamClient Function({required Uri host, required String username, required String password})?
    clientFactory,
  }) : _clientFactory = clientFactory ?? _defaultClientFactory;

  final EpgRepository _epgRepository;
  final XmltvEpgWriter _writer;
  final SourceRepository _sources;
  final SecureCredentialStore _secureStore;
  final XtreamClient Function({required Uri host, required String username, required String password})
  _clientFactory;

  static XtreamClient _defaultClientFactory({
    required Uri host,
    required String username,
    required String password,
  }) => XtreamClient(
    host: host,
    username: username,
    password: password,
    transport: RetryingXtreamTransport(HttpXtreamTransport()),
  );

  /// `true` si escribió programas nuevos en `epg_programmes` para
  /// [channel]; `false` en cualquier otro caso — ya había guía, no es un
  /// canal Xtream con `x-xtream-stream-id` conocido (ver
  /// `XtreamMapper.liveStreamToChannel`), la fuente no tiene credencial
  /// guardada, o el panel no devolvió nada útil dentro de la ventana.
  Future<bool> ensureEpgFor(Channel channel, {required DateTime now}) async {
    if (channel.type != ContentType.live) return false;
    final tvgId = channel.tvgId;
    if (tvgId == null) return false;
    final streamId = channel.metadata['x-xtream-stream-id'];
    if (streamId == null) return false;

    try {
      final window = XmltvWindow.around(now);
      final existing = await _epgRepository.programmesFor(tvgId, from: window.from, to: window.to);
      if (existing.isNotEmpty) return false;

      final source = await _sources.getById(channel.sourceId);
      final config = source?.config;
      if (config is! XtreamSourceConfig) return false;

      final secret = await _secureStore.read(channel.sourceId);
      if (secret == null) return false;

      final client = _clientFactory(host: config.host, username: config.username, password: secret);
      final result = await client.simpleDataTable(streamId);
      if (result is XtreamErr<List<XtreamEpgListing>>) return false;

      final listings = (result as XtreamOk<List<XtreamEpgListing>>).value;
      final entries = xtreamEpgToEntries(tvgId: tvgId, listings: listings, window: window).toList();
      if (entries.isEmpty) return false;

      await _writer.write(Stream.fromIterable(entries), now: now);
      return true;
    } catch (_) {
      return false;
    }
  }
}
