import 'package:drift/drift.dart';

/// Espejo de `Channel` (`iptv_core`). `id` es un autoincremental
/// puramente físico — existe solo para que FTS5 (`fts.drift`) pueda
/// enlazar `content_rowid` a una columna real (SQLite no deja apuntar
/// una external content table a su `rowid` implícito de forma fiable
/// para drift_dev). La identidad lógica sigue siendo `(sourceId,
/// refKey)` — `refKey` es `ChannelRef.key` (T1.6, ADR-003), la que
/// sobrevive a un refresco de la fuente o a una transferencia entre
/// dispositivos; `favorites`/`watch_state` referencian por ahí, nunca
/// por `id`.
// `ChannelRow`, no `Channel`: evita colisión con la entidad `Channel`
// de iptv_core.
@DataClassName('ChannelRow')
// S5 · Ola 1 (esquema v3): sin estos dos índices, el listado paginado
// de `channelsPage`/`countChannels` (`ChannelRepository`) es un
// scan+sort completo de la tabla en cada página — inviable sobre 100k
// filas (RNF-01). `idx_channels_type_name` cubre el listado por
// sección (TV/Cine/Series) ordenado alfabéticamente;
// `idx_channels_category_name` cubre el filtro por categoría dentro de
// una sección. Ver `migration_v3_test.dart` (verifica con `EXPLAIN
// QUERY PLAN` que se usan, no solo que existen).
@TableIndex(name: 'idx_channels_type_name', columns: {#contentType, #name})
@TableIndex(
  name: 'idx_channels_category_name',
  columns: {#categoryId, #name},
)
class Channels extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get sourceId => text()();
  TextColumn get refKey => text()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get contentType => text()();
  TextColumn get name => text()();
  TextColumn get url => text()();
  TextColumn get tvgId => text().nullable()();
  TextColumn get logo => text().nullable()();

  /// Atributos crudos no modelados (`group-title`, `#EXTVLCOPT`...),
  /// serializados como JSON.
  TextColumn get metadataJson => text().withDefault(const Constant('{}'))();

  /// Tombstone **local** (T1.6b, esquema v2) — no confundir con
  /// [SyncableColumns.deletedAt]: `Channel` no implementa `Syncable` (no
  /// participa en el merge LWW, ver `syncable.dart`), así que esto no
  /// viaja entre dispositivos. Existe únicamente para que
  /// `importSourceContent` pueda marcar un canal ausente de la fuente sin
  /// borrar la fila — y así preservar el favorito/watch-state que
  /// referencia su `(sourceId, refKey)` si el canal reaparece en un
  /// refresco posterior.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  /// Hash de detección de cambios (`content_hash.dart`) sobre los campos
  /// de contenido (no la identidad `sourceId`/`refKey`). Nullable porque
  /// las filas creadas antes de esta columna (esquema v1) no tienen uno
  /// — `importSourceContent` las trata como "cambiadas" en su próximo
  /// refresco, que es la política correcta: sin un hash previo real no
  /// hay forma honesta de decir que "no cambiaron".
  TextColumn get contentHash => text().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {sourceId, refKey},
  ];
}
