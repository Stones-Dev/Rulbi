import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../common/byte_decoding.dart';

/// Decodifica un M3U de bytes crudos a líneas de texto completas,
/// detectando el encoding **antes** de decodificar (nunca se asume UTF-8 a
/// ciegas) y tolerando CRLF/LF mixto. Streaming de verdad: solo se
/// bufferiza una ventana acotada al principio para detectar el encoding
/// (BOM o heurística), nunca el archivo completo.
///
/// Orden de detección:
/// 1. BOM UTF-8 (`EF BB BF`) → UTF-8, BOM descartado.
/// 2. BOM UTF-16 LE (`FF FE`) / BE (`FE FF`) → UTF-16, BOM descartado.
/// 3. Sin BOM: se intenta decodificar la ventana de sniff como UTF-8
///    estricto; si falla (secuencia inválida — típico de Latin-1 con
///    tildes, que no es UTF-8 válido), se asume Latin-1.
Stream<String> decodeM3uLines(Stream<List<int>> bytes) {
  return _decodeM3uBytes(bytes).transform(const LineSplitter());
}

/// Bytes bufferizados como mínimo para decidir el encoding cuando no hay
/// BOM: suficiente para que un carácter no-ASCII de las primeras líneas
/// (p. ej. un `group-title` con tilde) entre en la ventana de sniff. No es
/// "cargar el archivo entero": es una ventana acotada, independiente del
/// tamaño total del M3U.
const int _sniffWindowBytes = 4096;

enum _DetectedEncoding { utf8, latin1, utf16le, utf16be }

Stream<String> _decodeM3uBytes(Stream<List<int>> bytes) async* {
  final iterator = StreamIterator(bytes);
  final buffer = await bufferSniffWindow(iterator, _sniffWindowBytes);

  final encoding = _detectEncoding(buffer);
  final prefix = _stripBom(buffer, encoding);
  final combined = prependBytes(prefix, restOf(iterator));

  switch (encoding) {
    case _DetectedEncoding.utf8:
      yield* utf8.decoder.bind(combined);
    case _DetectedEncoding.latin1:
      yield* latin1.decoder.bind(combined);
    case _DetectedEncoding.utf16le:
      yield* Utf16Decoder(endian: Endian.little).bind(combined);
    case _DetectedEncoding.utf16be:
      yield* Utf16Decoder(endian: Endian.big).bind(combined);
  }
}

_DetectedEncoding _detectEncoding(List<int> prefix) {
  if (prefix.length >= 3 &&
      prefix[0] == 0xEF &&
      prefix[1] == 0xBB &&
      prefix[2] == 0xBF) {
    return _DetectedEncoding.utf8;
  }
  if (prefix.length >= 2 && prefix[0] == 0xFF && prefix[1] == 0xFE) {
    return _DetectedEncoding.utf16le;
  }
  if (prefix.length >= 2 && prefix[0] == 0xFE && prefix[1] == 0xFF) {
    return _DetectedEncoding.utf16be;
  }
  try {
    utf8.decode(prefix, allowMalformed: false);
    return _DetectedEncoding.utf8;
  } on FormatException {
    return _DetectedEncoding.latin1;
  }
}

List<int> _stripBom(List<int> prefix, _DetectedEncoding encoding) =>
    switch (encoding) {
      _DetectedEncoding.utf8 when prefix.length >= 3 && prefix[0] == 0xEF =>
        prefix.sublist(3),
      _DetectedEncoding.utf16le ||
      _DetectedEncoding.utf16be when prefix.length >= 2 => prefix.sublist(2),
      _ => prefix,
    };
