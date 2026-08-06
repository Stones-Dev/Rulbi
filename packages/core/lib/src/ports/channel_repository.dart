import '../entities/category.dart';
import '../entities/channel.dart';

abstract interface class ChannelRepository {
  /// Importa el contenido de una fuente de forma diferencial (T1.6b): un
  /// canal nuevo se inserta, uno con el mismo `ChannelRef` pero contenido
  /// distinto se actualiza, uno que ya no aparece en [channels] se marca
  /// `deletedAt` (tombstone local, no se borra la fila), y uno tumbado
  /// que reaparece se resucita. Preserva favoritos y watch-state, que se
  /// indexan por `ChannelRef` y no por el `id` de fila (ver ADR-003).
  ///
  /// [now] lo decide quien orquesta (`ManageSources`), nunca `data` — el
  /// repositorio no añade lógica de negocio sobre el reloj, solo persiste
  /// con el instante que le dan.
  ///
  /// Sustituye a un `replaceSourceContent` anterior (borrado completo +
  /// reinserción) que nunca llegó a implementarse como diferencial pese a
  /// su nombre.
  Future<SourceImportStats> importSourceContent(
    String sourceId,
    Stream<Channel> channels, {
    required DateTime now,
  });

  Future<List<Category>> categoriesFor(String sourceId);

  /// Nº de canales vivos de una fuente (`deletedAt IS NULL`) — los
  /// tombstones de [importSourceContent] no son canales del usuario
  /// (Gestión de fuentes, ui-spec §2.10). No trae filas, solo cuenta.
  Future<int> countBySource(String sourceId);

  Stream<List<Channel>> watchChannels({required String categoryId});

  /// Purga de tombstones huérfanos ("Tombstones huérfanos (purga)", S2):
  /// borra de verdad las filas `deletedAt` no nulo (tombstone local de
  /// T1.6b) que ya no protegen ningún favorito ni watch-state vivo, y
  /// cuyo tombstone es más antiguo que [deletedBefore] (ventana de gracia
  /// configurable — si el canal reaparece antes, `importSourceContent` lo
  /// resucita en su lugar sin tocar esta purga).
  ///
  /// "Vivo" = fila de favorito/watch-state existente con `deletedAt IS
  /// NULL`; un favorito ya tumbado por el merge LWW no protege al canal.
  /// Devuelve el número de filas borradas.
  Future<int> purgeOrphanTombstones({required DateTime deletedBefore});
}

/// Recuento de lo que hizo un [ChannelRepository.importSourceContent] — la
/// mitad de "upsert" del informe de descartes (T1.9); vive en `core`
/// porque es vocabulario de dominio (a diferencia de `ImportReport` de
/// `protocols`, que es vocabulario del formato de origen, ver P6).
final class SourceImportStats {
  const SourceImportStats({
    required this.inserted,
    required this.updated,
    required this.unchanged,
    required this.tombstoned,
    required this.resurrected,
    required this.duplicateRefs,
  });

  /// Canales nuevos (su `ChannelRef` no existía para esta fuente).
  final int inserted;

  /// Canales existentes cuyo contenido cambió (ver `content_hash.dart`
  /// en `data`).
  final int updated;

  /// Canales existentes cuyo contenido no cambió — no generan ningún
  /// `UPDATE` (ver riesgo de churn de FTS5 en el diseño de T1.6b).
  final int unchanged;

  /// Canales que existían y no aparecieron en este import: se marcan
  /// `deletedAt`, no se borran (tombstone local).
  final int tombstoned;

  /// Canales que estaban tumbados (`deletedAt` no nulo) y reaparecieron.
  final int resurrected;

  /// Canales con el mismo `ChannelRef` repetidos dentro del *mismo*
  /// import (p. ej. dos entradas M3U sin `tvg-id` que normalizan al
  /// mismo nombre) — gana el último, se cuenta para que T1.9 lo muestre.
  final int duplicateRefs;

  Map<String, Object?> toJson() => {
    'inserted': inserted,
    'updated': updated,
    'unchanged': unchanged,
    'tombstoned': tombstoned,
    'resurrected': resurrected,
    'duplicateRefs': duplicateRefs,
  };

  factory SourceImportStats.fromJson(Map<String, Object?> json) =>
      SourceImportStats(
        inserted: json['inserted'] as int,
        updated: json['updated'] as int,
        unchanged: json['unchanged'] as int,
        tombstoned: json['tombstoned'] as int,
        resurrected: json['resurrected'] as int,
        duplicateRefs: json['duplicateRefs'] as int,
      );

  @override
  bool operator ==(Object other) =>
      other is SourceImportStats &&
      other.inserted == inserted &&
      other.updated == updated &&
      other.unchanged == unchanged &&
      other.tombstoned == tombstoned &&
      other.resurrected == resurrected &&
      other.duplicateRefs == duplicateRefs;

  @override
  int get hashCode => Object.hash(
    inserted,
    updated,
    unchanged,
    tombstoned,
    resurrected,
    duplicateRefs,
  );

  @override
  String toString() =>
      'SourceImportStats(inserted: $inserted, updated: $updated, '
      'unchanged: $unchanged, tombstoned: $tombstoned, '
      'resurrected: $resurrected, duplicateRefs: $duplicateRefs)';
}
