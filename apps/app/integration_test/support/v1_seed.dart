import 'package:iptv_data/testing.dart' as v1;

/// Siembra A+B de ADR-007 (verificación de migraciones drift en Android
/// runtime): ~24 filas reales sobre el esquema v1 (antes de
/// `deleted_at`/`content_hash` en `channels`, columnas de la migración
/// v1->v2 de T1.6b), cruzando canales + favoritos + watch-state. Matriz
/// completa documentada en el plan de la sesión (D4) — cada combinación
/// relevante (favorito solo, watch-state solo, ambos, ninguno, favorito
/// tombstoneado, mismo `refKey` en dos fuentes distintas, diacríticos
/// para FTS5) tiene su fila.
class SeedChannel {
  const SeedChannel({
    required this.sourceId,
    required this.refKey,
    required this.name,
    this.categoryId,
  });

  final String sourceId;
  final String refKey;
  final String name;
  final String? categoryId;

  String get url => 'http://example.com/$sourceId/$refKey';
}

const List<SeedChannel> seedChannels = [
  SeedChannel(
    sourceId: 's1',
    refKey: 'c01',
    name: 'Canal Uno',
    categoryId: 'cat-news',
  ),
  SeedChannel(
    sourceId: 's1',
    refKey: 'c02',
    name: 'Canal Dos',
    categoryId: 'cat-news',
  ),
  SeedChannel(
    sourceId: 's1',
    refKey: 'c03',
    name: 'Canal Tres',
    categoryId: 'cat-sport',
  ),
  SeedChannel(
    sourceId: 's1',
    refKey: 'c04',
    name: 'Canal Cuatro',
    categoryId: 'cat-sport',
  ),
  SeedChannel(
    sourceId: 's1',
    refKey: 'c05',
    name: 'España Directo',
    categoryId: 'cat-news',
  ),
  SeedChannel(
    sourceId: 's1',
    refKey: 'c06',
    name: 'Ñandú TV',
    categoryId: 'cat-sport',
  ),
  SeedChannel(sourceId: 's1', refKey: 'c07', name: 'Canal Ünicode'),
  SeedChannel(
    sourceId: 's1',
    refKey: 'c08',
    name: 'Deportes 24h',
    categoryId: 'cat-sport',
  ),
  SeedChannel(sourceId: 's1', refKey: 'c09', name: 'Cine Clásico'),
  SeedChannel(
    sourceId: 's1',
    refKey: 'c10',
    name: 'Canal Diez',
    categoryId: 'cat-news',
  ),
  SeedChannel(sourceId: 's2', refKey: 'c01', name: 'Canal Uno (secundaria)'),
  SeedChannel(sourceId: 's2', refKey: 'c02', name: 'Canal Dos (secundaria)'),
];

const int expectedSourceCount = 2;
const int expectedCategoryCount = 2;
const int expectedChannelCount = 12;
const int expectedFavoriteCount = 4;
const int expectedWatchStateCount = 4;

// (s1, c01): favorito + watch-state (la única fila con posición/duración
// afirmadas literalmente tras la migración).
const int c01PositionMs = 125000;
const int c01DurationMs = 3600000;

// (s1, c05): favorito tombstoneado (sobrevive como tal a la migración,
// ADR-003/LWW) + watch-state. Fecha del tombstone: 2026-01-02T00:00:00Z.
final int c05TombstoneEpochSeconds =
    DateTime.utc(2026, 1, 2).millisecondsSinceEpoch ~/ 1000;

/// `drift_dev schema dump` no captura triggers como entidades de esquema
/// (comprobado: `drift_schemas/drift_schema_v1.json` sólo tiene entidades
/// `table`/`index`, ninguna `trigger` — misma familia de limitación que
/// el workaround de `channels_fts_au` documentado en ADR-004/T1.6b). Una
/// instalación v1 real SIEMPRE tuvo estos triggers activos desde T1.5a
/// ("FTS5 verificado: insert/update/delete") — sin ellos, la BD v1 de
/// este test no sería una réplica fiel de una real. Se recrean aquí
/// literalmente (copia de `packages/data/lib/src/db/fts.drift`) antes de
/// sembrar, para que las filas insertadas se indexen igual que en
/// producción.
Future<void> createFtsSyncTriggers(v1.DatabaseAtV1 db) async {
  await db.customStatement('''
CREATE TRIGGER channels_fts_ai AFTER INSERT ON channels BEGIN
  INSERT INTO channels_fts(rowid, name) VALUES (new.id, new.name);
END;
''');
  await db.customStatement('''
CREATE TRIGGER channels_fts_ad AFTER DELETE ON channels BEGIN
  INSERT INTO channels_fts(channels_fts, rowid, name) VALUES('delete', old.id, old.name);
END;
''');
  await db.customStatement('''
CREATE TRIGGER channels_fts_au AFTER UPDATE ON channels BEGIN
  INSERT INTO channels_fts(channels_fts, rowid, name) VALUES('delete', old.id, old.name);
  INSERT INTO channels_fts(rowid, name) VALUES (new.id, new.name);
END;
''');
}

Future<void> seedV1Database(v1.DatabaseAtV1 db) async {
  await createFtsSyncTriggers(db);

  await db.customStatement(
    'INSERT INTO sources (id, kind, name, config_json, enabled, refresh_policy) '
    "VALUES (?, 'm3uUrl', ?, '{}', 1, 'manual')",
    ['s1', 'Fuente principal'],
  );
  await db.customStatement(
    'INSERT INTO sources (id, kind, name, config_json, enabled, refresh_policy) '
    "VALUES (?, 'm3uUrl', ?, '{}', 1, 'manual')",
    ['s2', 'Fuente secundaria'],
  );

  await db.customStatement(
    'INSERT INTO categories (id, source_id, content_type, name, sort_order) '
    "VALUES (?, 's1', 'live', ?, 0)",
    ['cat-news', 'Noticias'],
  );
  await db.customStatement(
    'INSERT INTO categories (id, source_id, content_type, name, sort_order) '
    "VALUES (?, 's1', 'live', ?, 1)",
    ['cat-sport', 'Deportes'],
  );

  for (final channel in seedChannels) {
    await db.customStatement(
      'INSERT INTO channels (source_id, ref_key, category_id, content_type, '
      'name, url) VALUES (?, ?, ?, ?, ?, ?)',
      [
        channel.sourceId,
        channel.refKey,
        channel.categoryId,
        'live',
        channel.name,
        channel.url,
      ],
    );
  }

  // Favoritos: (s1,c01) y (s1,c02) vivos, (s2,c01) vivo (mismo refKey que
  // s1/c01 — verifica el aislamiento por sourceId), (s1,c05) tombstoneado.
  await db.customStatement(
    "INSERT INTO favorites (source_id, ref_key) VALUES ('s1', 'c01')",
  );
  await db.customStatement(
    "INSERT INTO favorites (source_id, ref_key) VALUES ('s1', 'c02')",
  );
  await db.customStatement(
    "INSERT INTO favorites (source_id, ref_key) VALUES ('s2', 'c01')",
  );
  await db.customStatement(
    'INSERT INTO favorites (source_id, ref_key, deleted_at) '
    "VALUES ('s1', 'c05', ?)",
    [c05TombstoneEpochSeconds],
  );

  // Watch-state: c01 con valores exactos afirmados en el test; c03/c05/c08
  // con valores no nulos pero no afirmados literalmente (solo se comprueba
  // que sobreviven y son legibles vía el repositorio tras la migración).
  await db.customStatement(
    'INSERT INTO watch_state (source_id, ref_key, position_ms, duration_ms) '
    "VALUES ('s1', 'c01', ?, ?)",
    [c01PositionMs, c01DurationMs],
  );
  await db.customStatement(
    'INSERT INTO watch_state (source_id, ref_key, position_ms, duration_ms) '
    "VALUES ('s1', 'c03', 30000, 0)",
  );
  await db.customStatement(
    'INSERT INTO watch_state (source_id, ref_key, position_ms, duration_ms) '
    "VALUES ('s1', 'c05', 600000, 0)",
  );
  await db.customStatement(
    'INSERT INTO watch_state (source_id, ref_key, position_ms, duration_ms) '
    "VALUES ('s1', 'c08', 15000, 0)",
  );
}
