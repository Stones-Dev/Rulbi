import 'package:iptv_core/iptv_core.dart';

import 'import_report.dart';
import 'm3u_encoding.dart';

/// Eventos internos del parser núcleo (no isolate-aware — eso lo añade el
/// wrapper público `parseM3u` de `m3u_parser.dart`, spawneando esta función
/// dentro de un `Isolate`). Se testea directamente para no pagar el coste
/// de un isolate real en cada test de caso límite.
sealed class M3uCoreEvent {}

/// Un lote de canales parseados con éxito (nunca canal a canal: "isolate +
/// lotes").
final class M3uChannelBatch extends M3uCoreEvent {
  M3uChannelBatch(this.channels);
  final List<Channel> channels;
}

/// Una línea que no se pudo asociar a ningún canal válido. Nunca se lanza
/// una excepción por esto (P7): se reporta y se sigue.
final class M3uDiscard extends M3uCoreEvent {
  M3uDiscard(this.line);
  final DiscardedLine line;
}

/// Parsea un M3U en streaming: decodifica el encoding correcto, tolera
/// CRLF/LF mixto, acumula directivas intermedias (`#EXTVLCOPT`,
/// `#KODIPROP`, `#EXTBACKUP`, cualquier `#EXT*` desconocido) entre
/// `#EXTINF` y la URL sin asumir adyacencia estricta, y emite canales en
/// lotes de [batchSize].
Stream<M3uCoreEvent> parseM3uCore({
  required Stream<List<int>> bytes,
  required String sourceId,
  int batchSize = 500,
}) async* {
  var lineNumber = 0;
  _ChannelBuilder? open;
  var batch = <Channel>[];

  await for (final rawLine in decodeM3uLines(bytes)) {
    lineNumber++;
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#EXTM3U')) continue;

    if (line.startsWith('#EXTINF:')) {
      if (open != null) {
        // #EXTINF colgado: otro #EXTINF lo interrumpió antes de su URL.
        yield M3uDiscard(
          DiscardedLine(
            lineNumber: open.lineNumber,
            rawLine: open.rawExtinf,
            reason: '#EXTINF sin URL antes de la siguiente entrada',
          ),
        );
      }
      open = _ChannelBuilder.fromExtinf(lineNumber: lineNumber, rawLine: line);
      continue;
    }

    if (line.startsWith('#')) {
      // Directiva huérfana (sin #EXTINF abierto): se ignora en silencio —
      // no es uno de los dos casos de descarte documentados, es ruido de
      // formato, no una entrada de canal fallida.
      open?.addDirective(line);
      continue;
    }

    // Línea sin '#': URL (con posible sufijo `|...`).
    if (open == null) {
      yield M3uDiscard(
        DiscardedLine(
          lineNumber: lineNumber,
          rawLine: line,
          reason: 'URL sin #EXTINF previo',
        ),
      );
      continue;
    }

    final builder = open;
    open = null;
    final channel = builder.build(sourceId: sourceId, urlLine: line);
    if (channel == null) {
      yield M3uDiscard(
        DiscardedLine(lineNumber: lineNumber, rawLine: line, reason: 'URL inválida'),
      );
      continue;
    }

    batch.add(channel);
    if (batch.length >= batchSize) {
      yield M3uChannelBatch(List.unmodifiable(batch));
      batch = <Channel>[];
    }
  }

  if (open != null) {
    yield M3uDiscard(
      DiscardedLine(
        lineNumber: open.lineNumber,
        rawLine: open.rawExtinf,
        reason: '#EXTINF sin URL antes de fin de archivo',
      ),
    );
  }

  if (batch.isNotEmpty) {
    yield M3uChannelBatch(List.unmodifiable(batch));
  }
}

/// Acumulador de un canal "en construcción": desde que se ve un `#EXTINF`
/// hasta que llega su línea de URL (o se interrumpe/EOF, ver arriba).
class _ChannelBuilder {
  _ChannelBuilder._({
    required this.lineNumber,
    required this.rawExtinf,
    required this.attrs,
    required this.displayName,
  });

  factory _ChannelBuilder.fromExtinf({
    required int lineNumber,
    required String rawLine,
  }) {
    final content = rawLine.substring('#EXTINF:'.length);
    final commaIndex = _firstUnquotedComma(content);
    final attrsSegment = commaIndex >= 0
        ? content.substring(0, commaIndex)
        : content;
    final name = commaIndex >= 0
        ? content.substring(commaIndex + 1).trim()
        : '';
    return _ChannelBuilder._(
      lineNumber: lineNumber,
      rawExtinf: rawLine,
      attrs: _parseAttrs(attrsSegment),
      displayName: name,
    );
  }

  final int lineNumber;
  final String rawExtinf;

  /// Atributos crudos del `#EXTINF` (`tvg-id`, `tvg-logo`, `group-title`,
  /// `catchup`, `catchup-days`, `catchup-source`, cualquier otro).
  final Map<String, String> attrs;
  final String displayName;

  /// `#EXTBACKUP:<url>` acumuladas, en orden.
  final List<String> fallbackUrls = [];

  /// `#EXTVLCOPT`/`#KODIPROP`/`#EXT*` desconocidas, ya con su clave de
  /// metadata (`x-vlcopt-*`, `x-kodiprop-*`, `x-ext-*`) resuelta.
  final Map<String, String> directiveMetadata = {};

  void addDirective(String line) {
    final colon = line.indexOf(':');
    final tag = (colon >= 0 ? line.substring(1, colon) : line.substring(1))
        .toUpperCase();
    final rest = colon >= 0 ? line.substring(colon + 1) : '';

    switch (tag) {
      case 'EXTVLCOPT':
        final eq = rest.indexOf('=');
        if (eq > 0) {
          directiveMetadata['x-vlcopt-${rest.substring(0, eq)}'] = rest
              .substring(eq + 1);
        }
      case 'KODIPROP':
        final eq = rest.indexOf('=');
        if (eq > 0) {
          directiveMetadata['x-kodiprop-${rest.substring(0, eq)}'] = rest
              .substring(eq + 1);
        }
      case 'EXTBACKUP':
        final url = rest.trim();
        if (url.isNotEmpty) fallbackUrls.add(url);
      default:
        // #EXT* desconocida: se conserva igualmente, nada se pierde en
        // silencio (P7).
        if (rest.isNotEmpty) {
          directiveMetadata['x-ext-${tag.toLowerCase()}'] = rest;
        }
    }
  }

  Channel? build({required String sourceId, required String urlLine}) {
    final segments = urlLine.split('|');
    final primary = segments.first.trim();
    if (primary.isEmpty) return null;
    final uri = Uri.tryParse(primary);
    if (uri == null) return null;

    final metadata = <String, String>{...directiveMetadata};
    for (final entry in attrs.entries) {
      if (entry.key == 'tvg-id' || entry.key == 'tvg-logo') {
        continue; // ya modelados como campos propios de Channel.
      }
      metadata[entry.key] = entry.value;
    }

    // Sufijo(s) tras '|': cada segmento se evalúa por separado — si TODAS
    // sus partes (unidas por '&', al estilo query-string) tienen forma
    // clave=valor se trata como cabeceras Kodi; si NINGUNA la tiene, como
    // URL de fallback. Ambigüedad real del formato (ver
    // pipe_separated_fallback.m3u): esta es la mejor heurística posible,
    // no una certeza — documentado también en el propio fixture.
    for (final suffix in segments.skip(1)) {
      final parts = suffix.split('&');
      final allKeyValue = parts.every((p) => p.contains('='));
      if (allKeyValue) {
        for (final part in parts) {
          final eq = part.indexOf('=');
          final key = part.substring(0, eq).trim().toLowerCase();
          final value = part.substring(eq + 1).trim();
          switch (key) {
            case 'user-agent':
              metadata['x-http-user-agent'] = value;
            case 'referer':
            case 'referrer':
              metadata['x-http-referrer'] = value;
            default:
              metadata['x-http-$key'] = value;
          }
        }
      } else {
        final url = suffix.trim();
        if (url.isNotEmpty) fallbackUrls.add(url);
      }
    }

    if (fallbackUrls.isNotEmpty) {
      metadata['x-fallback-urls'] = fallbackUrls.join(',');
    }

    final tvgId = attrs['tvg-id'];
    final tvgLogo = attrs['tvg-logo'];
    final groupTitle = attrs['group-title'];

    return Channel(
      ref: ChannelRef.derive(
        sourceId: sourceId,
        tvgId: tvgId,
        url: primary,
        name: displayName,
      ),
      sourceId: sourceId,
      categoryId: (groupTitle != null && groupTitle.isNotEmpty)
          ? Category.derive(
              sourceId: sourceId,
              type: ContentType.live,
              name: groupTitle,
            ).id
          : null,
      // M3U puro no distingue live/vod/series de forma fiable (a
      // diferencia de un panel Xtream, ver T1.4); se asume live por
      // defecto — decisión reversible, ningún fixture real la contradice.
      type: ContentType.live,
      name: displayName,
      url: uri,
      tvgId: tvgId,
      logo: (tvgLogo != null && tvgLogo.isNotEmpty)
          ? Uri.tryParse(tvgLogo)
          : null,
      metadata: metadata,
    );
  }
}

int _firstUnquotedComma(String s) {
  var inQuotes = false;
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    if (ch == '"') inQuotes = !inQuotes;
    if (ch == ',' && !inQuotes) return i;
  }
  return -1;
}

final RegExp _attrPattern = RegExp(r'([A-Za-z0-9_-]+)=(?:"([^"]*)"|(\S+))');

Map<String, String> _parseAttrs(String segment) {
  final result = <String, String>{};
  for (final match in _attrPattern.allMatches(segment)) {
    final key = match.group(1)!;
    final value = match.group(2) ?? match.group(3) ?? '';
    result[key] = value;
  }
  return result;
}
