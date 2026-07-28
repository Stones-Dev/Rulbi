import 'dart:math';

import 'package:iptv_pairing/iptv_pairing.dart';
import 'package:test/test.dart';

void main() {
  group('SixDigitCode.generate', () {
    test(
      'siempre produce exactamente 6 dígitos, incluso con ceros a la izquierda',
      () {
        // Random determinista que fuerza nextInt(1000000) == 42 → "000042".
        final code = SixDigitCode.generate(random: _FixedRandom(42));
        expect(code.value, '000042');
        expect(SixDigitCode.isWellFormed(code.value), isTrue);
      },
    );

    test('nunca genera un valor fuera de 000000–999999', () {
      for (var i = 0; i < 50; i++) {
        final code = SixDigitCode.generate();
        expect(SixDigitCode.isWellFormed(code.value), isTrue);
      }
    });
  });

  group('matches', () {
    test('solo coincide con el valor exacto', () {
      final code = SixDigitCode('123456');
      expect(code.matches('123456'), isTrue);
      expect(code.matches('123457'), isFalse);
      expect(code.matches(' 123456'), isFalse);
    });
  });

  test('isWellFormed rechaza longitudes y caracteres inválidos', () {
    expect(SixDigitCode.isWellFormed('123456'), isTrue);
    expect(SixDigitCode.isWellFormed('12345'), isFalse);
    expect(SixDigitCode.isWellFormed('1234567'), isFalse);
    expect(SixDigitCode.isWellFormed('12345a'), isFalse);
  });
}

final class _FixedRandom implements Random {
  _FixedRandom(this._value);
  final int _value;

  @override
  int nextInt(int max) => _value;

  @override
  double nextDouble() => 0;

  @override
  bool nextBool() => false;
}
