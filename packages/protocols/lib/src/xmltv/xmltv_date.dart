/// Parseo tolerante de fechas XMLTV (formato `YYYYMMDDHHMMSS ±HHMM` del
/// DTD, más las variantes reales que se observan en el ecosistema: sin
/// espacio antes del offset, offset con dos puntos, `Z`/`UTC` como
/// alternativa al offset numérico, y precisión truncada — el DTD permite
/// `YYYY`, `YYYYMM`, `YYYYMMDD`, `YYYYMMDDHH`, `YYYYMMDDHHMM` además de la
/// forma completa).
///
/// P7 (tolerancia): esta función nunca lanza. Una cadena irreconocible
/// devuelve `null` — quien llama la convierte en un descarte reportado,
/// nunca en una excepción que aborte el import.
library;

/// Resultado de un parseo con éxito. [dateTime] siempre está en UTC
/// (offset ya aplicado). [assumedUtc] es `true` cuando la cadena de
/// origen no traía ningún offset horario — el dato se conserva (P7), pero
/// el llamador puede usar la marca para contarlo en el informe
/// (`XmltvImportReport.assumedUtcDates`) en vez de descartarlo en
/// silencio.
final class XmltvDateResult {
  const XmltvDateResult({required this.dateTime, required this.assumedUtc});

  final DateTime dateTime;
  final bool assumedUtc;

  @override
  String toString() =>
      'XmltvDateResult($dateTime, assumedUtc: $assumedUtc)';
}

/// `YYYY[MM[DD[HH[MM[SS]]]]]` seguido, opcionalmente, de espacio en
/// blanco y un offset (`Z`, `UTC`, `GMT`, o `[+-]HH:?MM`). El offset
/// siempre empieza por un carácter no numérico, así que no hay ambigüedad
/// con el bloque de dígitos de la fecha (que es voraz por diseño).
final RegExp _pattern = RegExp(
  r'^(\d{4,14})\s*(Z|UTC|GMT|[+-]\d{2}:?\d{2})?$',
  caseSensitive: false,
);

const Set<int> _validDigitLengths = {4, 6, 8, 10, 12, 14};

XmltvDateResult? parseXmltvDate(String raw) {
  final match = _pattern.firstMatch(raw.trim());
  if (match == null) return null;

  final digits = match.group(1)!;
  if (!_validDigitLengths.contains(digits.length)) return null;

  final year = int.parse(digits.substring(0, 4));
  final month = digits.length >= 6 ? int.parse(digits.substring(4, 6)) : 1;
  final day = digits.length >= 8 ? int.parse(digits.substring(6, 8)) : 1;
  final hour = digits.length >= 10 ? int.parse(digits.substring(8, 10)) : 0;
  final minute = digits.length >= 12 ? int.parse(digits.substring(10, 12)) : 0;
  final second = digits.length >= 14 ? int.parse(digits.substring(12, 14)) : 0;

  if (month < 1 ||
      month > 12 ||
      day < 1 ||
      day > 31 ||
      hour > 23 ||
      minute > 59 ||
      second > 59) {
    return null;
  }

  // DateTime.utc normaliza en vez de lanzar para un día fuera del mes
  // (p. ej. 31 de abril rueda a 1 de mayo) — se detecta comparando de
  // vuelta, en lugar de reimplementar una tabla de días por mes.
  final wallClock = DateTime.utc(year, month, day, hour, minute, second);
  if (wallClock.month != month || wallClock.day != day) return null;

  final offsetToken = match.group(2);
  if (offsetToken == null) {
    return XmltvDateResult(dateTime: wallClock, assumedUtc: true);
  }

  final upper = offsetToken.toUpperCase();
  if (upper == 'Z' || upper == 'UTC' || upper == 'GMT') {
    return XmltvDateResult(dateTime: wallClock, assumedUtc: false);
  }

  final sign = offsetToken.startsWith('-') ? -1 : 1;
  final offsetDigits = offsetToken.substring(1).replaceAll(':', '');
  final offsetHours = int.parse(offsetDigits.substring(0, 2));
  final offsetMinutes = int.parse(offsetDigits.substring(2, 4));
  if (offsetHours > 23 || offsetMinutes > 59) return null;

  final totalOffsetMinutes = sign * (offsetHours * 60 + offsetMinutes);
  return XmltvDateResult(
    // El instante UTC es el reloj de pared menos su offset: "10:30 en
    // UTC+2" son las 08:30 UTC.
    dateTime: wallClock.subtract(Duration(minutes: totalOffsetMinutes)),
    assumedUtc: false,
  );
}
