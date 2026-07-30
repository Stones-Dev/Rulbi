import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../common/byte_decoding.dart';

/// Decodifica bytes crudos de un XMLTV (posiblemente `.gz`) a texto,
/// detectando el encoding **antes** de decodificar (P1: nunca se asume
/// UTF-8 a ciegas, igual que M3U — `m3u_encoding.dart`). Streaming real:
/// gunzip incremental si hace falta, y solo se bufferiza una ventana
/// acotada para el sniff, nunca el documento completo.
///
/// Orden de detección (el mismo orden que aplica el propio estándar XML):
/// 1. Magic gzip (`1F 8B`) → gunzip al vuelo, y se vuelve a hacer sniff
///    sobre la cabecera ya descomprimida.
/// 2. BOM UTF-8 / UTF-16 LE / UTF-16 BE → gana sobre cualquier
///    declaración `encoding="..."` contradictoria.
/// 3. Declaración `<?xml ... encoding="..."?>` en los primeros bytes
///    (siempre ASCII puro, incluso si el resto del documento no lo es —
///    lo exige el propio estándar XML): UTF-8, ISO-8859-1/Latin-1,
///    Windows-1252 (aproximado a Latin-1: `dart:convert` no lo trae, y
///    solo difieren en 0x80–0x9F — comillas tipográficas, guiones
///    largos; documentado, no silencioso), US-ASCII.
/// 4. Sin BOM ni declaración reconocible: UTF-8 estricto con fallback a
///    Latin-1 (misma heurística que M3U).
Stream<String> decodeXmltvBytes(Stream<List<int>> bytes) async* {
  final magicIterator = StreamIterator(bytes);
  final magic = await bufferSniffWindow(magicIterator, 2);
  final isGzip = magic.length >= 2 && magic[0] == 0x1F && magic[1] == 0x8B;
  final rawBytes = prependBytes(magic, restOf(magicIterator));
  final xmlBytes = isGzip ? gzip.decoder.bind(rawBytes) : rawBytes;

  yield* _decodeXmlText(xmlBytes);
}

/// Bytes bufferizados como mínimo para detectar BOM/declaración: una
/// declaración XML real (`<?xml version="1.0" encoding="..."?>`) cabe
/// sobrada en esta ventana. No es "cargar el archivo entero" — ventana
/// acotada, independiente del tamaño total del documento (ya
/// descomprimido si venía en `.gz`).
const int _sniffWindowBytes = 1024;

enum _TextEncoding { utf8, latin1, utf16le, utf16be }

Stream<String> _decodeXmlText(Stream<List<int>> bytes) async* {
  final iterator = StreamIterator(bytes);
  final prefix = await bufferSniffWindow(iterator, _sniffWindowBytes);
  final rest = restOf(iterator);

  final bom = _detectBom(prefix);
  if (bom != null) {
    final stripped = prefix.sublist(bom.byteLength);
    yield* _decode(bom.encoding, prependBytes(stripped, rest));
    return;
  }

  final declaredName = _scanDeclaredEncodingName(prefix);
  final declaredEncoding = declaredName == null
      ? null
      : _mapDeclaredName(declaredName);
  final combined = prependBytes(prefix, rest);
  if (declaredEncoding != null) {
    yield* _decode(declaredEncoding, combined);
    return;
  }

  try {
    utf8.decode(prefix, allowMalformed: false);
    yield* utf8.decoder.bind(combined);
  } on FormatException {
    yield* latin1.decoder.bind(combined);
  }
}

class _BomMatch {
  const _BomMatch(this.encoding, this.byteLength);
  final _TextEncoding encoding;
  final int byteLength;
}

_BomMatch? _detectBom(List<int> prefix) {
  if (prefix.length >= 3 &&
      prefix[0] == 0xEF &&
      prefix[1] == 0xBB &&
      prefix[2] == 0xBF) {
    return const _BomMatch(_TextEncoding.utf8, 3);
  }
  if (prefix.length >= 2 && prefix[0] == 0xFF && prefix[1] == 0xFE) {
    return const _BomMatch(_TextEncoding.utf16le, 2);
  }
  if (prefix.length >= 2 && prefix[0] == 0xFE && prefix[1] == 0xFF) {
    return const _BomMatch(_TextEncoding.utf16be, 2);
  }
  return null;
}

final RegExp _declaredEncodingDouble = RegExp(
  r'''<\?xml[^>]*\bencoding\s*=\s*"([^"]+)"''',
);
final RegExp _declaredEncodingSingle = RegExp(
  r"""<\?xml[^>]*\bencoding\s*=\s*'([^']+)'""",
);

/// Escanea el `encoding="..."` de una declaración XML. Solo se fía del
/// tramo ASCII inicial: la declaración es siempre ASCII puro por el
/// propio estándar, así que cortar en el primer byte no-ASCII es seguro
/// — si hubiera declaración, ya habría terminado antes de ese byte.
String? _scanDeclaredEncodingName(List<int> prefix) {
  final ascii7 = StringBuffer();
  for (final byte in prefix) {
    if (byte > 0x7F) break;
    ascii7.writeCharCode(byte);
  }
  final text = ascii7.toString();
  final match =
      _declaredEncodingDouble.firstMatch(text) ??
      _declaredEncodingSingle.firstMatch(text);
  return match?.group(1);
}

_TextEncoding? _mapDeclaredName(String name) {
  switch (name.toLowerCase().replaceAll('_', '-')) {
    case 'utf-8':
    case 'utf8':
    case 'us-ascii':
    case 'ascii':
      return _TextEncoding.utf8;
    case 'iso-8859-1':
    case 'iso8859-1':
    case 'latin1':
    case 'latin-1':
    case 'windows-1252':
    case 'cp1252':
      return _TextEncoding.latin1;
    default:
      // Nombre no reconocido (p. ej. un charset CJK): se ignora la
      // declaración y se cae al heurístico UTF-8/Latin-1 de más abajo
      // en vez de fallar — más útil que abortar la importación entera.
      return null;
  }
}

Stream<String> _decode(_TextEncoding encoding, Stream<List<int>> bytes) {
  switch (encoding) {
    case _TextEncoding.utf8:
      return utf8.decoder.bind(bytes);
    case _TextEncoding.latin1:
      return latin1.decoder.bind(bytes);
    case _TextEncoding.utf16le:
      return Utf16Decoder(endian: Endian.little).bind(bytes);
    case _TextEncoding.utf16be:
      return Utf16Decoder(endian: Endian.big).bind(bytes);
  }
}
