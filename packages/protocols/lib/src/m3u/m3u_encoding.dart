import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

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
  final buffer = <int>[];
  while (buffer.length < _sniffWindowBytes) {
    if (!await iterator.moveNext()) break;
    buffer.addAll(iterator.current);
  }

  final encoding = _detectEncoding(buffer);
  final prefix = _stripBom(buffer, encoding);
  final rest = _restOf(iterator);
  final combined = _prepend(prefix, rest);

  switch (encoding) {
    case _DetectedEncoding.utf8:
      yield* utf8.decoder.bind(combined);
    case _DetectedEncoding.latin1:
      yield* latin1.decoder.bind(combined);
    case _DetectedEncoding.utf16le:
      yield* _Utf16Decoder(endian: Endian.little).bind(combined);
    case _DetectedEncoding.utf16be:
      yield* _Utf16Decoder(endian: Endian.big).bind(combined);
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

Stream<List<int>> _restOf(StreamIterator<List<int>> iterator) async* {
  while (await iterator.moveNext()) {
    yield iterator.current;
  }
}

Stream<List<int>> _prepend(List<int> prefix, Stream<List<int>> rest) async* {
  if (prefix.isNotEmpty) yield prefix;
  yield* rest;
}

/// `dart:convert` no trae un decoder UTF-16 — se implementa a mano. Cuida
/// el caso de que un chunk corte un code unit (2 bytes) por la mitad,
/// guardando el byte suelto para el siguiente chunk.
class _Utf16Decoder {
  _Utf16Decoder({required this.endian});

  final Endian endian;

  Stream<String> bind(Stream<List<int>> stream) async* {
    final pending = <int>[];
    await for (final chunk in stream) {
      pending.addAll(chunk);
      final usable = pending.length - (pending.length % 2);
      if (usable == 0) continue;
      final codeUnits = <int>[];
      for (var i = 0; i < usable; i += 2) {
        final b0 = pending[i];
        final b1 = pending[i + 1];
        codeUnits.add(
          endian == Endian.little ? (b1 << 8) | b0 : (b0 << 8) | b1,
        );
      }
      yield String.fromCharCodes(codeUnits);
      pending.removeRange(0, usable);
    }
    // Un byte suelto final (archivo truncado a medio code unit) no tiene
    // nada más con que emparejarse — se descarta silenciosamente, no hay
    // línea de M3U que pueda depender de él.
  }
}
