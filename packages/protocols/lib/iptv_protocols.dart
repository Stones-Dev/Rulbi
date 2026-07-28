/// Parsers M3U y XMLTV (streaming) + cliente Xtream. Dart puro, sin
/// Flutter — ver principio P1/P6 de la constitution en `.specify/`.
library;

export 'src/m3u/import_report.dart';

// La API pública del parser M3U (`parseM3u`/`M3uParseOutcome`, wrapper de
// isolate) se exporta aquí cuando esté lista (ver .specify/tasks.md T1.2).
// Hasta entonces, `parseM3uCore` (núcleo sin isolate) es intencionadamente
// interno: los tests de este mismo paquete lo importan directamente vía
// 'package:iptv_protocols/src/m3u/m3u_core_parser.dart'.
