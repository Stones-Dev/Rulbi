/// Parsers M3U y XMLTV (streaming) + cliente Xtream. Dart puro, sin
/// Flutter — ver principio P1/P6 de la constitution en `.specify/`.
library;

export 'src/m3u/import_report.dart';
export 'src/m3u/m3u_parser.dart' show M3uParseOutcome, parseM3u;

// `parseM3uCore` (núcleo sin isolate) es intencionadamente interno: los
// tests de este mismo paquete lo importan directamente vía
// 'package:iptv_protocols/src/m3u/m3u_core_parser.dart' para no pagar el
// coste de un isolate real en cada test de caso límite. La API pública
// para el resto del monorepo es `parseM3u`/`M3uParseOutcome` de arriba.
