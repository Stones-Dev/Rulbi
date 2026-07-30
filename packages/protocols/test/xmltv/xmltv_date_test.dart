import 'package:iptv_protocols/src/xmltv/xmltv_date.dart';
import 'package:test/test.dart';

void main() {
  group('parseXmltvDate', () {
    test('formato canónico con offset "+HHMM"', () {
      final result = parseXmltvDate('20260727103000 +0200');
      expect(result, isNotNull);
      expect(
        result!.dateTime,
        DateTime.utc(2026, 7, 27, 8, 30, 0),
        reason: '10:30 en UTC+2 es 08:30 UTC',
      );
      expect(result.assumedUtc, isFalse);
    });

    test('offset con dos puntos "+HH:MM" da el mismo instante que "+HHMM"', () {
      final withColon = parseXmltvDate('20260727103000 +02:00');
      final withoutColon = parseXmltvDate('20260727103000 +0200');
      expect(withColon, isNotNull);
      expect(withColon!.dateTime, withoutColon!.dateTime);
      expect(withColon.assumedUtc, isFalse);
    });

    test('sin espacio antes del offset', () {
      final result = parseXmltvDate('20260727103000+0200');
      expect(result, isNotNull);
      expect(result!.dateTime, DateTime.utc(2026, 7, 27, 8, 30, 0));
      expect(result.assumedUtc, isFalse);
    });

    test('offset "Z" (UTC explícito)', () {
      final result = parseXmltvDate('20260727103000Z');
      expect(result, isNotNull);
      expect(result!.dateTime, DateTime.utc(2026, 7, 27, 10, 30, 0));
      expect(
        result.assumedUtc,
        isFalse,
        reason: 'UTC está declarado explícitamente, no asumido',
      );
    });

    test('offset "UTC" literal', () {
      final result = parseXmltvDate('20260727103000 UTC');
      expect(result, isNotNull);
      expect(result!.dateTime, DateTime.utc(2026, 7, 27, 10, 30, 0));
      expect(result.assumedUtc, isFalse);
    });

    test('solo fecha (precisión truncada a día)', () {
      final result = parseXmltvDate('20260727');
      expect(result, isNotNull);
      expect(result!.dateTime, DateTime.utc(2026, 7, 27, 0, 0, 0));
      expect(result.assumedUtc, isTrue);
    });

    test('truncado a fecha+hora+minuto (sin segundos)', () {
      final result = parseXmltvDate('202607270025');
      expect(result, isNotNull);
      expect(result!.dateTime, DateTime.utc(2026, 7, 27, 0, 25, 0));
      expect(result.assumedUtc, isTrue);
    });

    test('sin offset horario: se asume UTC y se marca assumedUtc', () {
      final result = parseXmltvDate('20260727103000');
      expect(result, isNotNull);
      expect(result!.dateTime, DateTime.utc(2026, 7, 27, 10, 30, 0));
      expect(result.assumedUtc, isTrue);
    });

    test('cadena sin forma de fecha reconocible → null', () {
      expect(parseXmltvDate('no es una fecha'), isNull);
      expect(parseXmltvDate(''), isNull);
      expect(parseXmltvDate('20260732'), isNull, reason: 'día 32 no existe');
      expect(parseXmltvDate('20261301'), isNull, reason: 'mes 13 no existe');
    });

    test('offset con horas fuera de rango → null (rechazado, no asumido)', () {
      expect(parseXmltvDate('20260727103000 +9900'), isNull);
    });

    test('offset negativo se resta en la dirección correcta', () {
      final result = parseXmltvDate('20260727003000 -0500');
      expect(result, isNotNull);
      expect(
        result!.dateTime,
        DateTime.utc(2026, 7, 27, 5, 30, 0),
        reason: '00:30 en UTC-5 es 05:30 UTC del mismo día',
      );
    });
  });
}
