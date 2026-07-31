/// Arnés de esquemas históricos para tests de migración (T1.6b, ADR-007).
///
/// **Barrel separado de `iptv_data.dart` a propósito**: lo de aquí sólo
/// existe para verificar migraciones (host o runtime real), nunca para
/// producción. Vivió bajo `test/generated_migrations/` hasta que
/// ADR-007 (verificación de migraciones drift en Android runtime)
/// necesitó que `apps/app/integration_test/` pudiera construir una BD
/// v1 real — un directorio `test/` de un paquete no es alcanzable desde
/// fuera de él, así que el arnés se movió a `lib/src/testing/` y se
/// expone por este barrel.
///
/// `schema_v1.dart` es la salida literal de `drift_dev schema generate`
/// sobre `drift_schemas/drift_schema_v1.json` (T1.6b) — no se ha tocado
/// su contenido en el traslado, sólo la ruta del fichero.
library;

export 'src/testing/generated_migrations/schema.dart';
export 'src/testing/generated_migrations/schema_v1.dart';
