/// Primitivas de decodificación de bytes compartidas entre los parsers
/// M3U (T1.2) y XMLTV (T1.3): bufferizar una ventana de sniff acotada,
/// re-anteponerla al resto del stream sin perder ni duplicar bytes, y
/// decodificar UTF-16 a mano (`dart:convert` no trae un decoder UTF-16).
/// Cada formato conserva su propia heurística de *detección* de encoding
/// (M3U: BOM o UTF-8/Latin-1; XMLTV: BOM o `<?xml encoding="..."?>`) — solo
/// el mecanismo de streaming es común.
library;

import 'dart:async';
import 'dart:typed_data';

/// Consume del [iterator] hasta acumular al menos [windowBytes] (o hasta
/// que el stream se agote) y devuelve el buffer acumulado. No es "cargar
/// todo": es una ventana acotada, independiente del tamaño total de la
/// entrada — quien llama decide cuántos bytes necesita para su heurística
/// de detección de encoding.
Future<List<int>> bufferSniffWindow(
  StreamIterator<List<int>> iterator,
  int windowBytes,
) async {
  final buffer = <int>[];
  while (buffer.length < windowBytes) {
    if (!await iterator.moveNext()) break;
    buffer.addAll(iterator.current);
  }
  return buffer;
}

/// El resto de un stream ya parcialmente consumido por un
/// [StreamIterator], como stream propio.
Stream<List<int>> restOf(StreamIterator<List<int>> iterator) async* {
  while (await iterator.moveNext()) {
    yield iterator.current;
  }
}

/// Antepone [prefix] (ya consumido para el sniff de encoding) al resto de
/// bytes, sin duplicar ni perder ninguno.
Stream<List<int>> prependBytes(
  List<int> prefix,
  Stream<List<int>> rest,
) async* {
  if (prefix.isNotEmpty) yield prefix;
  yield* rest;
}

/// `dart:convert` no trae un decoder UTF-16 — se implementa a mano. Cuida
/// el caso de que un chunk corte un code unit (2 bytes) por la mitad,
/// guardando el byte suelto para el siguiente chunk.
class Utf16Decoder {
  Utf16Decoder({required this.endian});

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
    // dato que pueda depender de él.
  }
}
