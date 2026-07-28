import 'package:iptv_core/iptv_core.dart';

/// Orquesta el merge last-write-wins a nivel de **colección** (T1.7):
/// qué clave está en un lado y no en el otro, tombstones vencidos... La
/// regla de decisión sobre un conflicto entre dos versiones del *mismo*
/// registro es de `core` (`resolveConflict`, ADR-003) — este motor la
/// reutiliza en vez de duplicarla, para que `data` y `pairing` nunca
/// puedan divergir sobre qué significa "gana el más reciente".
final class LwwMerger<T extends Syncable> {
  LwwMerger({required this.keyOf, required this.tiebreaker});

  /// Clave lógica estable del registro (p. ej. `ChannelRef` para
  /// [Favorite]/[WatchState], `deviceId` para `PairedDevice`).
  final Object Function(T item) keyOf;
  final Tiebreaker<T> tiebreaker;

  /// Fusiona dos colecciones de la misma entidad. Determinista y
  /// **simétrico como conjunto**: `merge(a, b)` y `merge(b, a)` contienen
  /// exactamente los mismos elementos (el orden de la lista de salida no
  /// importa) — es la propiedad que hace que la sync converja sin
  /// importar qué dispositivo inició el intercambio.
  List<T> merge(List<T> local, List<T> remote) {
    final byKey = <Object, T>{};
    void fold(T item) {
      final key = keyOf(item);
      final existing = byKey[key];
      byKey[key] = existing == null
          ? item
          : resolveConflict(existing, item, tiebreaker: tiebreaker);
    }

    local.forEach(fold);
    remote.forEach(fold);
    return byKey.values.toList();
  }

  /// Recolecta tombstones vencidos: registros borrados hace más de
  /// [window] (30 días por defecto) ya no necesitan seguir viajando en
  /// cada merge — todo dispositivo emparejado ha tenido tiempo de sobra
  /// para verlos y aplicar el borrado.
  List<T> collectTombstones(
    List<T> items, {
    required DateTime now,
    Duration window = const Duration(days: 30),
  }) {
    return items.where((item) {
      if (!item.isDeleted) return true;
      return now.difference(item.deletedAt!) <= window;
    }).toList();
  }
}
