/// Puerto de tiempo inyectable. Sin él, cualquier test de merge LWW sería
/// no determinista (compararía contra `DateTime.now()` real). Se usa en
/// todos los casos de uso que fijan `updatedAt` de una entidad
/// [Syncable] y en el protocolo de sesión de `pairing` (TTLs).
abstract interface class Clock {
  DateTime now();
}

/// Implementación real para producción. Pura Dart — `DateTime.now()` no
/// requiere ninguna API de plataforma, así que vive aquí sin romper P6.
final class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now().toUtc();
}
