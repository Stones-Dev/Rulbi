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

// `parseM3uCore`/`parseXmltvCore` (núcleos sin isolate) son
// intencionadamente internos: los tests de este mismo paquete los
// importan directamente vía 'package:iptv_protocols/src/.../..._core_parser.dart'
// para no pagar el coste de un isolate real en cada test de caso límite.
// La API pública para el resto del monorepo es `parseM3u`/`M3uParseOutcome`
// y `parseXmltv`/`XmltvParseOutcome` de arriba. `XmltvReportBuilder`
// (agregador interno reutilizado por el wrapper con isolate y por los
// tests) tampoco se exporta: quien use `parseXmltv` recibe el
// `XmltvImportReport` ya construido.
