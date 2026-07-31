/// Parsers M3U y XMLTV (streaming) + cliente Xtream. Dart puro, sin
/// Flutter — ver principio P1/P6 de la constitution en `.specify/`.
library;

export 'src/m3u/import_report.dart';
export 'src/m3u/m3u_parser.dart' show M3uParseOutcome, parseM3u;

export 'src/xmltv/xmltv_entry.dart'
    show XmltvChannel, XmltvChannelEntry, XmltvEntry, XmltvProgrammeEntry;
export 'src/xmltv/xmltv_parser.dart' show XmltvParseOutcome, parseXmltv;
export 'src/xmltv/xmltv_report.dart' show XmltvDiscard, XmltvImportReport;
export 'src/xmltv/xmltv_window.dart' show XmltvWindow;

// T1.4 — cliente Xtream Codes. `XtreamClient.importChannels()` es el
// equivalente Xtream de `parseM3u`: un `Stream<Channel>` que entra tal
// cual en `ManageSources`. Los DTOs de protocolo (categorías, streams,
// series/episodios) y `XtreamUrlResolver`/`XtreamMapper` se exponen para
// que `packages/data`/`packages/player` puedan construir pantallas de
// detalle (ficha de serie, "probar conexión") sin pasar por un import
// completo.
export 'src/xtream/xtream_account.dart' show XtreamAccount;
export 'src/xtream/xtream_category.dart' show XtreamCategory;
export 'src/xtream/xtream_client.dart' show XtreamClient, XtreamImportOutcome;
export 'src/xtream/xtream_epg.dart' show XtreamEpgListing;
export 'src/xtream/xtream_failure.dart'
    show
        XtreamAccountDisabled,
        XtreamAccountExpired,
        XtreamAuthFailed,
        XtreamErr,
        XtreamFailure,
        XtreamHttpFailure,
        XtreamMalformed,
        XtreamNetworkFailure,
        XtreamOk,
        XtreamRateLimited,
        XtreamResult;
export 'src/xtream/xtream_import_report.dart' show XtreamDiscard, XtreamImportReport;
export 'src/xtream/xtream_mapper.dart' show XtreamMapper;
export 'src/xtream/xtream_series.dart'
    show XtreamEpisode, XtreamSeason, XtreamSeries, XtreamSeriesInfo;
export 'src/xtream/xtream_stream.dart' show XtreamLiveStream;
export 'src/xtream/xtream_transport.dart'
    show HttpXtreamTransport, RetryingXtreamTransport, XtreamHttpResponse, XtreamTransport;
export 'src/xtream/xtream_url_resolver.dart' show XtreamUrlResolver;
export 'src/xtream/xtream_vod.dart' show XtreamVodInfo, XtreamVodStream;

// `parseM3uCore`/`parseXmltvCore` (núcleos sin isolate) son
// intencionadamente internos: los tests de este mismo paquete los
// importan directamente vía 'package:iptv_protocols/src/.../..._core_parser.dart'
// para no pagar el coste de un isolate real en cada test de caso límite.
// La API pública para el resto del monorepo es `parseM3u`/`M3uParseOutcome`
// y `parseXmltv`/`XmltvParseOutcome` de arriba. `XmltvReportBuilder`
// (agregador interno reutilizado por el wrapper con isolate y por los
// tests) tampoco se exporta: quien use `parseXmltv` recibe el
// `XmltvImportReport` ya construido.
