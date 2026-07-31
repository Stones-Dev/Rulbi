import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_data/iptv_data.dart';

/// "Tombstones huérfanos (purga)" (S2): borra de verdad los canales
/// tumbados (T1.6b, `channels.deleted_at`) que ya no protegen ningún
/// favorito ni watch-state vivo, tras una ventana de gracia configurable.
/// Mismo arranque que `import_differential_test.dart` — SQLite real
/// (`NativeDatabase.memory()`), mide semántica, no jank (eso lo cubre el
/// benchmark de sanity aparte).
void main() {
  late IptvDatabase db;
  late DriftChannelRepository channels;
  late DriftFavoritesRepository favorites;
  late DriftWatchStateRepository watchState;

  setUp(() {
    db = IptvDatabase(NativeDatabase.memory());
    channels = DriftChannelRepository(db);
    favorites = DriftFavoritesRepository(db);
    watchState = DriftWatchStateRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  const ref = ChannelRef(sourceId: 's1', key: 'a');

  Future<void> importAndTombstone({
    required DateTime importedAt,
    required DateTime tombstonedAt,
  }) async {
    await channels.importSourceContent(
      's1',
      Stream.fromIterable([
        Channel(
          ref: ref,
          sourceId: 's1',
          type: ContentType.live,
          name: 'Canal',
          url: Uri.parse('http://example.com/stream'),
        ),
      ]),
      now: importedAt,
    );
    // Ausencia en el import siguiente -> tombstone (T1.6b).
    await channels.importSourceContent(
      's1',
      const Stream<Channel>.empty(),
      now: tombstonedAt,
    );
  }

  Future<List<ChannelRow>> rawRowsFor(String sourceId) => (db.select(
    db.channels,
  )..where((c) => c.sourceId.equals(sourceId))).get();

  final now = DateTime.utc(2026, 3, 10);
  const grace = Duration(days: 30);
  final tombstonedLongAgo = now.subtract(const Duration(days: 40));

  group('"Hecho cuando" — favorito vivo protege, nada asociado se purga', () {
    test('un tombstone con favorito vivo sobrevive', () async {
      await importAndTombstone(
        importedAt: DateTime.utc(2026, 1, 1),
        tombstonedAt: tombstonedLongAgo,
      );
      await favorites.upsert(Favorite(channel: ref, updatedAt: tombstonedLongAgo));

      final deleted = await channels.purgeOrphanTombstones(
        deletedBefore: now.subtract(grace),
      );

      expect(deleted, 0);
      final row = (await rawRowsFor('s1')).single;
      expect(row.deletedAt, isNotNull);
    });

    test('un tombstone sin favorito ni watch-state se purga', () async {
      await importAndTombstone(
        importedAt: DateTime.utc(2026, 1, 1),
        tombstonedAt: tombstonedLongAgo,
      );

      final deleted = await channels.purgeOrphanTombstones(
        deletedBefore: now.subtract(grace),
      );

      expect(deleted, 1);
      expect(await rawRowsFor('s1'), isEmpty);
    });
  });

  test('un tombstone con watch-state vivo sobrevive', () async {
    await importAndTombstone(
      importedAt: DateTime.utc(2026, 1, 1),
      tombstonedAt: tombstonedLongAgo,
    );
    await watchState.upsert(
      WatchState(
        channel: ref,
        position: const Duration(minutes: 5),
        duration: const Duration(minutes: 50),
        updatedAt: tombstonedLongAgo,
      ),
    );

    final deleted = await channels.purgeOrphanTombstones(
      deletedBefore: now.subtract(grace),
    );

    expect(deleted, 0);
    expect(await rawRowsFor('s1'), hasLength(1));
  });

  test(
    'un favorito ya borrado (tombstone LWW) no protege: el canal se purga '
    'igual',
    () async {
      await importAndTombstone(
        importedAt: DateTime.utc(2026, 1, 1),
        tombstonedAt: tombstonedLongAgo,
      );
      final favorite = Favorite(channel: ref, updatedAt: tombstonedLongAgo);
      await favorites.upsert(favorite);
      await favorites.upsert(favorite.markDeleted(tombstonedLongAgo));

      final deleted = await channels.purgeOrphanTombstones(
        deletedBefore: now.subtract(grace),
      );

      expect(deleted, 1);
      expect(await rawRowsFor('s1'), isEmpty);
    },
  );

  group('ventana de gracia configurable', () {
    test('tumbado ayer, con gracia de 30 días: sobrevive', () async {
      await importAndTombstone(
        importedAt: DateTime.utc(2026, 1, 1),
        tombstonedAt: now.subtract(const Duration(days: 1)),
      );

      final deleted = await channels.purgeOrphanTombstones(
        deletedBefore: now.subtract(const Duration(days: 30)),
      );

      expect(deleted, 0);
      expect(await rawRowsFor('s1'), hasLength(1));
    });

    test('el mismo tombstone, con gracia 0: se purga', () async {
      await importAndTombstone(
        importedAt: DateTime.utc(2026, 1, 1),
        tombstonedAt: now.subtract(const Duration(days: 1)),
      );

      final deleted = await channels.purgeOrphanTombstones(
        deletedBefore: now,
      );

      expect(deleted, 1);
      expect(await rawRowsFor('s1'), isEmpty);
    });
  });

  test('un canal vivo, por viejo que sea, nunca se toca', () async {
    await channels.importSourceContent(
      's1',
      Stream.fromIterable([
        Channel(
          ref: ref,
          sourceId: 's1',
          type: ContentType.live,
          name: 'Canal',
          url: Uri.parse('http://example.com/stream'),
        ),
      ]),
      now: DateTime.utc(2020, 1, 1),
    );

    final deleted = await channels.purgeOrphanTombstones(
      deletedBefore: now,
    );

    expect(deleted, 0);
    final row = (await rawRowsFor('s1')).single;
    expect(row.deletedAt, isNull);
  });

  group('idempotencia', () {
    test('dos corridas seguidas: la segunda no borra nada más', () async {
      await importAndTombstone(
        importedAt: DateTime.utc(2026, 1, 1),
        tombstonedAt: tombstonedLongAgo,
      );

      final first = await channels.purgeOrphanTombstones(
        deletedBefore: now.subtract(grace),
      );
      expect(first, 1);

      final second = await channels.purgeOrphanTombstones(
        deletedBefore: now.subtract(grace),
      );
      expect(second, 0);
    });
  });

  group('FTS5', () {
    test(
      'tras purgar, search ya no lo devuelve y el índice sigue íntegro',
      () async {
        await importAndTombstone(
          importedAt: DateTime.utc(2026, 1, 1),
          tombstonedAt: tombstonedLongAgo,
        );

        await channels.purgeOrphanTombstones(deletedBefore: now.subtract(grace));

        expect(await channels.search('canal'), isEmpty);
        // 'integrity-check' lanza si el contenido externo (channels) y el
        // índice FTS5 (channels_fts) se desincronizaron.
        await db.customStatement(
          "INSERT INTO channels_fts(channels_fts) VALUES('integrity-check')",
        );
      },
    );
  });
}
