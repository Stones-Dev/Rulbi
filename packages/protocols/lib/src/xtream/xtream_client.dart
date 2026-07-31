import 'dart:async';
import 'dart:convert';

import 'package:iptv_core/iptv_core.dart' show Channel;

import 'xtream_account.dart';
import 'xtream_category.dart';
import 'xtream_epg.dart';
import 'xtream_failure.dart';
import 'xtream_import_report.dart';
import 'xtream_json.dart';
import 'xtream_mapper.dart';
import 'xtream_series.dart';
import 'xtream_stream.dart';
import 'xtream_transport.dart';
import 'xtream_vod.dart';

/// Cliente de la API Xtream Codes (`player_api.php`), T1.4. Dart puro, sin
/// Flutter (P6): la red entra por [XtreamTransport], no por una
/// dependencia de plataforma. Un método por acción (auth,
/// live/vod/series + info, categorías) en vez de un objeto único de
/// streams entrelazados — cada acción tiene su propia forma de fallo y su
/// propio test (P7); `importChannels()` (T1.4, bloque de import) es la
/// composición encima, no la única puerta.
///
/// La contraseña se guarda privada y no sale nunca del cliente: no
/// aparece en ningún [XtreamFailure], en ningún log ni en `toString()`.
/// El llamador la obtiene de `SecureCredentialStore` justo antes de
/// construir este cliente (P5) — `XtreamClient` no sabe de dónde vino.
/// Resultado de [XtreamClient.importChannels]: el stream de canales
/// (pásalo tal cual a `ManageSources.addSource`/`refreshSource`, igual
/// que `M3uParseOutcome.channels`) y, una vez que termina de emitir, el
/// informe de tolerancia.
final class XtreamImportOutcome {
  const XtreamImportOutcome({required this.channels, required this.report});

  final Stream<Channel> channels;

  /// Completa cuando [channels] agota su emisión (con éxito o con error).
  final Future<XtreamImportReport> report;
}

final class XtreamClient {
  XtreamClient({
    required this.host,
    required this.username,
    required this._password,
    required this._transport,
  });

  /// `host:puerto` del panel (ui-spec §2.9), sin `player_api.php` — se
  /// añade internamente. Mismo campo que [XtreamSourceConfig.host] en
  /// `core`.
  final Uri host;
  final String username;
  final String _password;
  final XtreamTransport _transport;

  Uri _playerApiUrl({String? action, Map<String, String>? extra}) {
    final query = <String, String>{
      'username': username,
      'password': _password,
      'action': ?action,
      ...?extra,
    };
    return host.replace(
      path: '${host.path.endsWith('/') ? host.path.substring(0, host.path.length - 1) : host.path}/player_api.php',
      queryParameters: query,
    );
  }

  /// `player_api.php?username=...&password=...` sin `action=` — el
  /// equivalente a la autenticación inicial de un cliente Xtream real
  /// (mismo endpoint que devuelve `user_info`/`server_info`).
  Future<XtreamResult<XtreamAccount>> authenticate() async {
    final bodyResult = await _getJsonBody(_playerApiUrl());
    if (bodyResult is XtreamErr<Object?>) {
      return XtreamErr(bodyResult.failure);
    }
    final decoded = (bodyResult as XtreamOk<Object?>).value;
    if (decoded is! Map) {
      return const XtreamErr(
        XtreamMalformed(reason: 'se esperaba un objeto JSON en la respuesta de autenticación'),
      );
    }

    final userInfo = asFlexibleMap(decoded['user_info']);
    if (userInfo.isEmpty) {
      // Panel que no reconoce al usuario suele omitir `user_info` por
      // completo (o devolverlo vacío) en vez de mandar `auth: 0` — ambas
      // formas son "no autenticado".
      return const XtreamErr(XtreamAuthFailed());
    }

    final auth = asFlexibleInt(userInfo['auth']);
    final rawStatus = asFlexibleString(userInfo['status']) ?? 'Unknown';
    final normalizedStatus = rawStatus.trim().toLowerCase();
    final message = asFlexibleString(userInfo['message']);

    if (auth != 1) {
      return XtreamErr(
        XtreamAuthFailed(message: (message != null && message.isNotEmpty) ? message : null),
      );
    }

    if (normalizedStatus == 'banned' || normalizedStatus == 'disabled') {
      return XtreamErr(XtreamAccountDisabled(rawStatus));
    }

    final expSeconds = asFlexibleIntOrNull(userInfo['exp_date']);
    final expiresAt = expSeconds != null
        ? DateTime.fromMillisecondsSinceEpoch(expSeconds * 1000, isUtc: true)
        : null;
    final isExpiredByDate = expiresAt != null && expiresAt.isBefore(DateTime.now().toUtc());

    if (normalizedStatus == 'expired' || isExpiredByDate) {
      return XtreamErr(XtreamAccountExpired(expiresAt: expiresAt));
    }

    final formats = asFlexibleList(userInfo['allowed_output_formats'])
        .map((e) => asFlexibleString(e) ?? '')
        .where((s) => s.isNotEmpty)
        .toList();

    return XtreamOk(
      XtreamAccount(
        username: asFlexibleString(userInfo['username']) ?? username,
        status: rawStatus,
        isTrial: asFlexibleBool(userInfo['is_trial']),
        activeConnections: asFlexibleInt(userInfo['active_cons']),
        maxConnections: asFlexibleInt(userInfo['max_connections'], fallback: 1),
        expiresAt: expiresAt,
        allowedOutputFormats: formats,
      ),
    );
  }

  Future<XtreamResult<List<XtreamCategory>>> liveCategories() =>
      _getCategories('get_live_categories');

  Future<XtreamResult<List<XtreamCategory>>> vodCategories() =>
      _getCategories('get_vod_categories');

  Future<XtreamResult<List<XtreamCategory>>> seriesCategories() =>
      _getCategories('get_series_categories');

  /// `get_live_streams`, opcionalmente filtrado por `category_id` (mismo
  /// parámetro que acepta el panel real). Entradas que no son un objeto
  /// JSON dentro del array se descartan silenciosamente a este nivel —
  /// la tolerancia de campo a campo dentro de cada objeto la hace
  /// [XtreamLiveStream.fromJson] vía `xtream_json.dart`.
  Future<XtreamResult<List<XtreamLiveStream>>> liveStreams({String? categoryId}) async {
    final listResult = await _getJsonList(
      _playerApiUrl(
        action: 'get_live_streams',
        extra: categoryId == null ? null : {'category_id': categoryId},
      ),
    );
    if (listResult is XtreamErr<List<Object?>>) {
      return XtreamErr(listResult.failure);
    }
    final items = (listResult as XtreamOk<List<Object?>>).value;
    return XtreamOk([
      for (final item in items)
        if (item is Map) XtreamLiveStream.fromJson(asFlexibleMap(item)),
    ]);
  }

  /// `get_vod_streams`, opcionalmente filtrado por `category_id`.
  Future<XtreamResult<List<XtreamVodStream>>> vodStreams({String? categoryId}) async {
    final listResult = await _getJsonList(
      _playerApiUrl(
        action: 'get_vod_streams',
        extra: categoryId == null ? null : {'category_id': categoryId},
      ),
    );
    if (listResult is XtreamErr<List<Object?>>) {
      return XtreamErr(listResult.failure);
    }
    final items = (listResult as XtreamOk<List<Object?>>).value;
    return XtreamOk([
      for (final item in items)
        if (item is Map) XtreamVodStream.fromJson(asFlexibleMap(item)),
    ]);
  }

  /// `get_vod_info&vod_id=...` — ficha completa de una película. Un
  /// `vod_id` inválido suele volver como `[]` o `{}` en vez de un error
  /// HTTP (dialecto real de paneles Xtream) — se trata como
  /// [XtreamMalformed], nunca como un `XtreamVodInfo` con campos vacíos
  /// inventados.
  Future<XtreamResult<XtreamVodInfo>> vodInfo(String vodId) async {
    final objResult = await _getJsonObject(
      _playerApiUrl(action: 'get_vod_info', extra: {'vod_id': vodId}),
    );
    if (objResult is XtreamErr<Map<String, Object?>>) {
      return XtreamErr(objResult.failure);
    }
    final json = (objResult as XtreamOk<Map<String, Object?>>).value;
    if (asFlexibleMap(json['movie_data']).isEmpty && asFlexibleMap(json['info']).isEmpty) {
      return const XtreamErr(
        XtreamMalformed(reason: 'get_vod_info sin "info" ni "movie_data" (vod_id probablemente inválido)'),
      );
    }
    return XtreamOk(XtreamVodInfo.fromJson(json));
  }

  /// `get_series`, opcionalmente filtrado por `category_id`. **No**
  /// trae temporadas/episodios — eso es [seriesInfo], una llamada por
  /// serie (ver `xtream_series.dart`).
  Future<XtreamResult<List<XtreamSeries>>> series({String? categoryId}) async {
    final listResult = await _getJsonList(
      _playerApiUrl(action: 'get_series', extra: categoryId == null ? null : {'category_id': categoryId}),
    );
    if (listResult is XtreamErr<List<Object?>>) {
      return XtreamErr(listResult.failure);
    }
    final items = (listResult as XtreamOk<List<Object?>>).value;
    return XtreamOk([
      for (final item in items)
        if (item is Map) XtreamSeries.fromJson(asFlexibleMap(item)),
    ]);
  }

  /// `get_series_info&series_id=...` — ficha completa con temporadas y
  /// episodios anidados. Mismo criterio que [vodInfo]: un `series_id`
  /// inválido que vuelva como `[]`/`{}` sin `info` ni `episodes` se trata
  /// como [XtreamMalformed], nunca como una ficha vacía inventada.
  Future<XtreamResult<XtreamSeriesInfo>> seriesInfo(String seriesId) async {
    final objResult = await _getJsonObject(
      _playerApiUrl(action: 'get_series_info', extra: {'series_id': seriesId}),
    );
    if (objResult is XtreamErr<Map<String, Object?>>) {
      return XtreamErr(objResult.failure);
    }
    final json = (objResult as XtreamOk<Map<String, Object?>>).value;
    final hasInfo = asFlexibleMap(json['info']).isNotEmpty;
    final hasEpisodes = json['episodes'] is Map
        ? asFlexibleMap(json['episodes']).isNotEmpty
        : asFlexibleList(json['episodes']).isNotEmpty;
    if (!hasInfo && !hasEpisodes) {
      return const XtreamErr(
        XtreamMalformed(reason: 'get_series_info sin "info" ni "episodes" (series_id probablemente inválido)'),
      );
    }
    return XtreamOk(XtreamSeriesInfo.fromJson(json));
  }

  /// `get_short_epg&stream_id=...&limit=...` — próximos programas de un
  /// canal live (ui-spec: "programa actual y siguiente"). No estaba entre
  /// las 9 actions capturadas en T1.1; cubierta con fixtures sintéticos
  /// documentados (ver `test/fixtures/xtream/synthetic/README.md`).
  Future<XtreamResult<List<XtreamEpgListing>>> shortEpg(String streamId, {int limit = 4}) => _getEpgListings(
    'get_short_epg',
    {'stream_id': streamId, 'limit': limit.toString()},
  );

  /// `get_simple_data_table&stream_id=...` — guía completa de un canal
  /// (equivalente a `get_short_epg` sin límite de entradas).
  Future<XtreamResult<List<XtreamEpgListing>>> simpleDataTable(String streamId) =>
      _getEpgListings('get_simple_data_table', {'stream_id': streamId});

  Future<XtreamResult<List<XtreamEpgListing>>> _getEpgListings(
    String action,
    Map<String, String> extra,
  ) async {
    final objResult = await _getJsonObject(_playerApiUrl(action: action, extra: extra));
    if (objResult is XtreamErr<Map<String, Object?>>) {
      return XtreamErr(objResult.failure);
    }
    final json = (objResult as XtreamOk<Map<String, Object?>>).value;
    // Un canal sin programación en el momento de la consulta puede volver
    // sin `epg_listings` en absoluto (dialecto observado en la
    // documentación pública) — se trata como "sin entradas", no como
    // fallo: no hay nada de malformado en que un canal no tenga guía.
    final listings = asFlexibleList(json['epg_listings']);
    return XtreamOk([
      for (final item in listings)
        if (item is Map) XtreamEpgListing.fromJson(asFlexibleMap(item)),
    ]);
  }

  /// Import completo de live + VOD (categorías + streams), en la misma
  /// forma que `parseM3u`/`M3uParseOutcome`: entra tal cual en
  /// `ManageSources.addSource`/`refreshSource` (T1.6b). Series **no**
  /// entra aquí — `get_series` no trae episodios, así que expandirlas
  /// exigiría un `get_series_info` por serie (N+1 de red inviable con un
  /// panel de miles de series); se piden bajo demanda al abrir la ficha
  /// (`seriesInfo()` + `XtreamMapper.episodeToChannel`).
  ///
  /// El parseo (fetch + mapeo) empieza solo cuando alguien escucha
  /// [XtreamImportOutcome.channels] (`onListen` diferido, mismo patrón que
  /// `parseM3u`): si nadie escucha, no se hace ninguna petición HTTP.
  ///
  /// Ninguna action fallida aborta el import completo (P7): un 500 en
  /// `get_vod_streams` no debe impedir importar los canales live que sí
  /// respondieron — se registra como [XtreamDiscard] y se sigue.
  ///
  /// **RNF-01**: el bucle de mapeo cede el event loop cada
  /// [cessionInterval] canales (`await Future<void>.delayed(Duration.zero)`,
  /// misma técnica que corrigió el jank real de T1.6b) — no se decodifica
  /// el JSON completo del panel en un isolate aparte todavía; el
  /// benchmark de sanity (T1.4, 50k streams sintéticos) mide si esta
  /// cesión basta o si hace falta escalar a un isolate, mismo criterio de
  /// "medir antes de complicar" que ya siguió T1.6b.
  XtreamImportOutcome importChannels({required String sourceId, int cessionInterval = 500}) {
    final controller = StreamController<Channel>();
    final reportCompleter = Completer<XtreamImportReport>();

    controller.onListen = () {
      unawaited(
        _runImport(sourceId: sourceId, cessionInterval: cessionInterval, controller: controller)
            .then(reportCompleter.complete)
            .catchError((Object error, StackTrace stack) {
              controller.addError(error, stack);
              if (!reportCompleter.isCompleted) {
                reportCompleter.completeError(error, stack);
              }
            })
            .whenComplete(controller.close),
      );
    };

    return XtreamImportOutcome(channels: controller.stream, report: reportCompleter.future);
  }

  Future<XtreamImportReport> _runImport({
    required String sourceId,
    required int cessionInterval,
    required StreamController<Channel> controller,
  }) async {
    final discarded = <XtreamDiscard>[];
    var discardedCount = 0;
    void discard(String action, String reason) {
      discardedCount++;
      if (discarded.length < XtreamImportReport.discardedCap) {
        discarded.add(XtreamDiscard(action: action, reason: reason));
      }
    }

    final liveCategoryNames = await _categoryNameMap(
      action: 'get_live_categories',
      fetch: liveCategories,
      onFailure: discard,
    );
    final vodCategoryNames = await _categoryNameMap(
      action: 'get_vod_categories',
      fetch: vodCategories,
      onFailure: discard,
    );

    var parsedLive = 0;
    final liveResult = await liveStreams();
    if (liveResult is XtreamErr<List<XtreamLiveStream>>) {
      discard('get_live_streams', liveResult.failure.toString());
    } else {
      final streams = (liveResult as XtreamOk<List<XtreamLiveStream>>).value;
      for (var i = 0; i < streams.length; i++) {
        controller.add(
          XtreamMapper.liveStreamToChannel(
            sourceId: sourceId,
            stream: streams[i],
            categoryNames: liveCategoryNames,
          ),
        );
        parsedLive++;
        if ((i + 1) % cessionInterval == 0) await Future<void>.delayed(Duration.zero);
      }
    }

    var parsedVod = 0;
    final vodResult = await vodStreams();
    if (vodResult is XtreamErr<List<XtreamVodStream>>) {
      discard('get_vod_streams', vodResult.failure.toString());
    } else {
      final streams = (vodResult as XtreamOk<List<XtreamVodStream>>).value;
      for (var i = 0; i < streams.length; i++) {
        controller.add(
          XtreamMapper.vodStreamToChannel(
            sourceId: sourceId,
            stream: streams[i],
            categoryNames: vodCategoryNames,
          ),
        );
        parsedVod++;
        if ((i + 1) % cessionInterval == 0) await Future<void>.delayed(Duration.zero);
      }
    }

    return XtreamImportReport(
      parsedLive: parsedLive,
      parsedVod: parsedVod,
      discardedCount: discardedCount,
      discarded: List.unmodifiable(discarded),
    );
  }

  /// `category_id` crudo → nombre, para las categorías de un solo tipo de
  /// contenido (live o vod) — ver `XtreamMapper.liveStreamToChannel`/
  /// `vodStreamToChannel`. Si la propia llamada de categorías falla, se
  /// registra el fallo y se sigue con un mapa vacío (los streams se
  /// mapean igual, degradados al `category_id` crudo como nombre).
  Future<Map<String, String>> _categoryNameMap({
    required String action,
    required Future<XtreamResult<List<XtreamCategory>>> Function() fetch,
    required void Function(String action, String reason) onFailure,
  }) async {
    final result = await fetch();
    if (result is XtreamErr<List<XtreamCategory>>) {
      onFailure(action, result.failure.toString());
      return const {};
    }
    final categories = (result as XtreamOk<List<XtreamCategory>>).value;
    return {for (final c in categories) c.id: c.name};
  }

  Future<XtreamResult<List<XtreamCategory>>> _getCategories(String action) async {
    final listResult = await _getJsonList(_playerApiUrl(action: action));
    if (listResult is XtreamErr<List<Object?>>) {
      return XtreamErr(listResult.failure);
    }
    final items = (listResult as XtreamOk<List<Object?>>).value;
    return XtreamOk([
      for (final item in items)
        if (item is Map) XtreamCategory.fromJson(asFlexibleMap(item)),
    ]);
  }

  /// Como [_getJsonBody] pero exige que el nivel superior decodifique a
  /// una `List` (todas las actions de listado de Xtream — categorías,
  /// streams, series — devuelven un array JSON) — un objeto donde se
  /// espera una lista (p. ej. un panel devolviendo `{}` en vez de `[]`
  /// cuando la cuenta no tiene contenido de ese tipo) se trata como
  /// malformado en vez de reventar con un `TypeError` en el llamador.
  Future<XtreamResult<List<Object?>>> _getJsonList(Uri url) async {
    final bodyResult = await _getJsonBody(url);
    if (bodyResult is XtreamErr<Object?>) {
      return XtreamErr(bodyResult.failure);
    }
    final decoded = (bodyResult as XtreamOk<Object?>).value;
    if (decoded is List) return XtreamOk(decoded);
    // Un panel sin contenido de un tipo a veces manda `{}`/`false` en vez
    // de `[]` — se trata como "lista vacía", no como error: no hay nada
    // de malformado en que una cuenta no tenga VOD, por ejemplo.
    if (decoded is Map && decoded.isEmpty) return const XtreamOk([]);
    if (decoded == false) return const XtreamOk([]);
    return const XtreamErr(
      XtreamMalformed(reason: 'se esperaba un array JSON en la respuesta'),
    );
  }

  /// Como [_getJsonList] pero para acciones que devuelven un único
  /// objeto (`get_vod_info`, `get_series_info`). Un `[]`/`{}` vacío —
  /// dialecto real cuando el id pedido no existe — se trata como
  /// malformado en vez de construir una entidad con campos inventados a
  /// partir de `{}`.
  Future<XtreamResult<Map<String, Object?>>> _getJsonObject(Uri url) async {
    final bodyResult = await _getJsonBody(url);
    if (bodyResult is XtreamErr<Object?>) {
      return XtreamErr(bodyResult.failure);
    }
    final decoded = (bodyResult as XtreamOk<Object?>).value;
    if (decoded is Map) return XtreamOk(asFlexibleMap(decoded));
    if (decoded is List && decoded.isEmpty) {
      return const XtreamErr(
        XtreamMalformed(reason: 'el panel devolvió un array vacío en vez de un objeto (id probablemente inválido)'),
      );
    }
    return const XtreamErr(XtreamMalformed(reason: 'se esperaba un objeto JSON'));
  }

  /// Petición GET + decodificación JSON común a todas las acciones:
  /// clasifica fallos de red/HTTP/rate-limit antes de intentar
  /// `jsonDecode`, y detecta HTML-en-vez-de-JSON (paneles caídos, portales
  /// cautivos, Cloudflare) *antes* de pasárselo al parser — nunca deja que
  /// `FormatException` se escape sin envolver.
  Future<XtreamResult<Object?>> _getJsonBody(Uri url) async {
    final XtreamHttpResponse response;
    try {
      response = await _transport.get(url);
    } catch (error) {
      return XtreamErr(XtreamNetworkFailure(_redactSecrets(error.toString())));
    }

    if (response.statusCode == 429) {
      return XtreamErr(XtreamRateLimited(retryAfter: response.retryAfter));
    }
    if (response.statusCode != 200) {
      return XtreamErr(XtreamHttpFailure(response.statusCode));
    }

    final text = response.bodyAsText;
    final trimmed = text.trimLeft();
    if (trimmed.isEmpty) {
      return const XtreamErr(XtreamMalformed(reason: 'cuerpo de respuesta vacío'));
    }

    final looksHtml =
        (response.contentType?.toLowerCase().contains('html') ?? false) ||
        trimmed.startsWith('<');
    if (looksHtml) {
      return XtreamErr(
        XtreamMalformed(
          reason: 'el panel devolvió HTML en vez de JSON',
          snippet: _snippet(trimmed),
        ),
      );
    }

    try {
      return XtreamOk(jsonDecode(text));
    } on FormatException catch (error) {
      return XtreamErr(
        XtreamMalformed(reason: 'JSON inválido: ${error.message}', snippet: _snippet(trimmed)),
      );
    }
  }

  static String _snippet(String text) => text.length <= 200 ? text : '${text.substring(0, 200)}…';

  /// Redacta `password=...` de cualquier mensaje de excepción antes de
  /// envolverlo en un [XtreamFailure] — `package:http` incluye la URL
  /// completa (con `username`/`password` como query params) en el
  /// `toString()` de sus excepciones de conexión (P5, test anti-fuga de
  /// credenciales).
  static String _redactSecrets(String message) =>
      message.replaceAll(RegExp('password=[^&\\s]*', caseSensitive: false), 'password=***');
}
