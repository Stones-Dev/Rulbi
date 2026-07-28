import 'syncable.dart';

/// Decide si [a] debe ganar el desempate frente a [b] cuando ambos tienen
/// exactamente el mismo `updatedAt`. Debe ser determinista y **simétrico**
/// sobre el *contenido* del registro — nunca sobre metadatos de proceso
/// (qué dispositivo escribió antes, orden de llegada de la red...) — para
/// que los dos lados de un merge lleguen a la misma decisión sin
/// coordinarse. Para cualquier par `a != b` debe cumplirse
/// `tiebreak(a, b) == !tiebreak(b, a)`: si no hay una respuesta única, el
/// merge no converge.
typedef Tiebreaker<T> = bool Function(T a, T b);

/// Resuelve qué versión de un mismo registro sincronizable sobrevive,
/// siguiendo la regla "last-write-wins" con tombstones (ADR-003):
///
/// 1. Gana el `updatedAt` estrictamente mayor.
/// 2. En empate exacto, decide [tiebreaker].
/// 3. Un tombstone (`deletedAt != null`) es un registro más a efectos de
///    esta comparación: si gana, gana el borrado — el merge no distingue
///    "borrar" de "escribir" en su regla de conflicto.
///
/// Esta función resuelve **un** conflicto entre dos versiones del mismo
/// registro. La orquestación a nivel de colección (qué claves están en
/// un lado y no en el otro, recolección de tombstones vencidos...) es
/// responsabilidad de `packages/pairing` (`LwwMerger`, T1.7): `core` solo
/// fija la regla de decisión que ambos lados deben compartir.
T resolveConflict<T extends Syncable>(
  T a,
  T b, {
  required Tiebreaker<T> tiebreaker,
}) {
  final byTime = a.updatedAt.compareTo(b.updatedAt);
  if (byTime != 0) return byTime > 0 ? a : b;
  return tiebreaker(a, b) ? a : b;
}
