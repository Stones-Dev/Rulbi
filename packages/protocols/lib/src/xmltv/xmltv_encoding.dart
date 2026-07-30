import 'dart:convert';

/// Decodifica bytes crudos de un XMLTV a texto.
///
/// **Versión mínima (T1.3, batería de núcleo SAX)**: solo UTF-8 directo.
/// La detección real de gunzip / BOM / `<?xml encoding="..."?>` se añade
/// en la batería de encoding dedicada — este archivo crece ahí con sus
/// propios tests antes de tocar la implementación, no se generaliza a
/// ciegas por adelantado.
Stream<String> decodeXmltvBytes(Stream<List<int>> bytes) {
  return utf8.decoder.bind(bytes);
}
