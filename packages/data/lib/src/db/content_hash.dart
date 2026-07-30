import 'dart:convert';

/// Los campos de un `Channel` que determinan si una fila de `channels`
/// "cambió" en un refresco diferencial (T1.6b). Deliberadamente **no**
/// incluye `sourceId` ni `ChannelRef.key` (`refKey`): esos son la identidad
/// de la fila, no su contenido — compararlos aquí no tendría sentido (una
/// fila nunca se compara contra otra de distinto refKey).
final class ChannelFields {
  const ChannelFields({
    required this.categoryId,
    required this.contentType,
    required this.name,
    required this.url,
    required this.tvgId,
    required this.logo,
    required this.metadataJson,
  });

  final String? categoryId;
  final String contentType;
  final String name;
  final String url;
  final String? tvgId;
  final String? logo;
  final String metadataJson;
}

/// Hash de detección de cambios sobre [ChannelFields]: es lo que
/// `DriftChannelRepository.importSourceContent` compara contra el
/// `content_hash` ya guardado para decidir si una fila necesita `UPDATE`,
/// sin tener que traer `url`/`metadataJson` (el grueso de la tabla) de las
/// 100k filas existentes para compararlas campo a campo.
///
/// FNV-1a de 32 bits en dos pasadas con offsets distintos (64 bits
/// efectivos) — no `Object.hash`/`String.hashCode`: ninguno de los dos es
/// estable entre procesos ni versiones del SDK de Dart, y este valor se
/// persiste en disco entre ejecuciones. Tampoco es SHA-256 a propósito:
/// esto es detección de cambios, no integridad criptográfica — con valores
/// reales la probabilidad de colisión de este esquema es del orden de
/// 1e-9/1e-10, y la consecuencia de una colisión es como mucho un `UPDATE`
/// omitido (el canal se queda con datos viejos hasta el próximo refresco
/// real), no corrupción de datos.
String channelContentHash(ChannelFields fields) {
  final buffer = StringBuffer();
  for (final field in [
    fields.categoryId,
    fields.contentType,
    fields.name,
    fields.url,
    fields.tvgId,
    fields.logo,
    fields.metadataJson,
  ]) {
    _writeField(buffer, field);
  }

  final bytes = utf8.encode(buffer.toString());
  final low = _fnv1a32(bytes, offsetBasis: _offsetBasisA);
  final high = _fnv1a32(bytes, offsetBasis: _offsetBasisB);
  return '${high.toRadixString(16).padLeft(8, '0')}'
      '${low.toRadixString(16).padLeft(8, '0')}';
}

/// Separador entre campos (Unit Separator, ASCII 0x1F): no aparece en texto
/// legible real (nombres de canal, URLs, JSON de metadata), así que casi
/// nunca hace falta escapar nada — pero si apareciera, [_writeEscaped] lo
/// neutraliza para que dos particiones de campos distintas nunca produzcan
/// la misma cadena concatenada (p. ej. `("a", "b")` vs `("a\x1fb", "")`).
const int _delimiter = 0x1f;
const int _backslash = 0x5c;

/// `null` marker: 0x00 nunca aparece en el resto de la codificación (ni
/// como separador ni como parte del escape), así que un campo ausente
/// nunca puede confundirse con uno presente pero vacío — sin este byte,
/// `categoryId: null` y `categoryId: ''` producirían la misma cadena.
const int _nullMarker = 0x00;
const int _presentMarker = 0x01;

/// Escribe un campo completo en [buffer]: un byte de presencia (para
/// distinguir `null` de `''`), el valor escapado si lo hay, y el
/// separador de campo.
void _writeField(StringBuffer buffer, String? value) {
  if (value == null) {
    buffer.writeCharCode(_nullMarker);
  } else {
    buffer.writeCharCode(_presentMarker);
    _writeEscaped(buffer, value);
  }
  buffer.writeCharCode(_delimiter);
}

/// Escribe [value] en [buffer], escapando la barra invertida como `\\` y
/// un separador literal como `\x1f` — en ese orden, para que un `\`
/// insertado por el propio escape de un separador no se confunda con una
/// barra invertida original del campo.
void _writeEscaped(StringBuffer buffer, String value) {
  for (final rune in value.runes) {
    if (rune == _backslash) {
      buffer.write(r'\\');
    } else if (rune == _delimiter) {
      buffer.write(r'\x1f');
    } else {
      buffer.writeCharCode(rune);
    }
  }
}

const int _fnvPrime32 = 0x01000193;
// Dos offsets distintos (el offset basis estándar de FNV-1a/32 y uno propio)
// para que las dos pasadas no sean la misma función con la misma entrada.
const int _offsetBasisA = 0x811c9dc5;
const int _offsetBasisB = 0xc9dc5811;
const int _mask32 = 0xFFFFFFFF;

int _fnv1a32(List<int> bytes, {required int offsetBasis}) {
  var hash = offsetBasis;
  for (final byte in bytes) {
    hash = (hash ^ byte) & _mask32;
    hash = (hash * _fnvPrime32) & _mask32;
  }
  return hash;
}
