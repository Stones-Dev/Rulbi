sealed class PairingSessionError implements Exception {
  const PairingSessionError(this.message);

  final String message;

  @override
  String toString() => message;
}

final class PairingTokenExpiredError extends PairingSessionError {
  const PairingTokenExpiredError()
    : super('El token de emparejamiento ha caducado.');
}

final class PairingTokenAlreadyUsedError extends PairingSessionError {
  const PairingTokenAlreadyUsedError()
    : super('El token de emparejamiento ya se usó.');
}

final class PairingAuthFactorRejectedError extends PairingSessionError {
  const PairingAuthFactorRejectedError() : super('Código o token incorrecto.');
}

final class PairingAttemptsExceededError extends PairingSessionError {
  const PairingAttemptsExceededError()
    : super('Demasiados intentos fallidos; sesión bloqueada.');
}
