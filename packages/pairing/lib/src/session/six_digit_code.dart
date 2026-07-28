import 'dart:math';

/// El código de 6 dígitos del flujo de emparejamiento sin cámara
/// (ui-spec §2.12/§3.1): el equivalente al QR para quien no puede
/// escanear. Ver la limitación de entropía documentada en
/// `SessionCrypto`.
final class SixDigitCode {
  SixDigitCode(this.value)
    : assert(isWellFormed(value), 'código mal formado: "$value"');

  final String value;

  static final RegExp _pattern = RegExp(r'^\d{6}$');

  /// Genera un código aleatorio con un generador criptográficamente
  /// seguro. Acepta un [random] alternativo solo para tests
  /// deterministas — nunca se usa `Random()` (no seguro) en producción.
  factory SixDigitCode.generate({Random? random}) {
    final rng = random ?? Random.secure();
    final number = rng.nextInt(1000000);
    return SixDigitCode(number.toString().padLeft(6, '0'));
  }

  static bool isWellFormed(String input) => _pattern.hasMatch(input);

  bool matches(String input) => input == value;

  @override
  bool operator ==(Object other) =>
      other is SixDigitCode && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
