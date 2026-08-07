import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_data/iptv_data.dart';

void main() {
  late IptvDatabase db;

  setUp(() {
    db = IptvDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('DriftSourceRepository', () {
    late DriftSourceRepository repository;

    setUp(() {
      repository = DriftSourceRepository(db);
    });

    test(
      'upsert + getById hace un round-trip fiel de un XtreamSourceConfig',
      () async {
        final source = Source(
          id: 's1',
          name: 'Mi panel',
          config: XtreamSourceConfig(
            host: Uri.parse('http://panel.example.com:8080'),
            username: 'usuario',
          ),
          updatedAt: DateTime(2026, 1, 1),
        );

        await repository.upsert(source);
        final found = await repository.getById('s1');

        expect(found, source);
      },
    );

    test(
      'upsert + getById hace un round-trip fiel de un M3uUrlSourceConfig',
      () async {
        final source = Source(
          id: 's2',
          name: 'Mi lista',
          config: M3uUrlSourceConfig(
            url: Uri.parse('http://example.com/list.m3u'),
            epgUrl: Uri.parse('http://example.com/epg.xml.gz'),
            userAgent: 'IPTVapp/1.0',
          ),
          updatedAt: DateTime(2026, 1, 1),
        );

        await repository.upsert(source);

        expect(await repository.getById('s2'), source);
      },
    );

    test('getById devuelve null si no existe', () async {
      expect(await repository.getById('no-existe'), isNull);
    });

    test('getAll devuelve todas las fuentes insertadas', () async {
      await repository.upsert(
        Source(
          id: 's1',
          name: 'A',
          config: const M3uFileSourceConfig(filePath: '/tmp/a.m3u'),
          updatedAt: DateTime(2026, 1, 1),
        ),
      );
      await repository.upsert(
        Source(
          id: 's2',
          name: 'B',
          config: const M3uFileSourceConfig(filePath: '/tmp/b.m3u'),
          updatedAt: DateTime(2026, 1, 1),
        ),
      );

      final all = await repository.getAll();
      expect(all.map((s) => s.id).toSet(), {'s1', 's2'});
    });

    test('upsert sobre el mismo id actualiza, no duplica', () async {
      final original = Source(
        id: 's1',
        name: 'Original',
        config: const M3uFileSourceConfig(filePath: '/tmp/a.m3u'),
        updatedAt: DateTime(2026, 1, 1),
      );
      await repository.upsert(original);
      await repository.upsert(original.withRefreshed(DateTime(2026, 1, 2)));

      final all = await repository.getAll();
      expect(all, hasLength(1));
      expect(all.single.lastRefresh, DateTime(2026, 1, 2));
    });
  });

  group('DriftChannelRepository', () {
    late DriftChannelRepository repository;

    setUp(() {
      repository = DriftChannelRepository(db);
    });

    Channel sampleChannel({required String refKey, required String name}) =>
        Channel(
          ref: ChannelRef(sourceId: 's1', key: refKey),
          sourceId: 's1',
          type: ContentType.live,
          name: name,
          url: Uri.parse('http://example.com/$refKey'),
          metadata: const {'group-title': 'General'},
        );

    test(
      'importSourceContent inserta y search los encuentra (acentos incluidos)',
      () async {
        await repository.importSourceContent(
          's1',
          Stream.fromIterable([
            sampleChannel(refKey: 'a', name: 'España TV'),
            sampleChannel(refKey: 'b', name: 'Otro canal'),
          ]),
          now: DateTime(2026, 1, 1),
        );

        final results = await repository.search('espana');
        expect(results.map((c) => c.name), ['España TV']);
        expect(results.single.metadata, {'group-title': 'General'});
      },
    );

    test(
      'importSourceContent no vuelve a mostrar un canal que desapareció de '
      'la fuente (tombstone, T1.6b — ver import_differential_test.dart '
      'para la batería completa del diff)',
      () async {
        await repository.importSourceContent(
          's1',
          Stream.fromIterable([
            sampleChannel(refKey: 'a', name: 'Canal viejo'),
          ]),
          now: DateTime(2026, 1, 1),
        );
        await repository.importSourceContent(
          's1',
          Stream.fromIterable([
            sampleChannel(refKey: 'b', name: 'Canal nuevo'),
          ]),
          now: DateTime(2026, 1, 2),
        );

        final results = await repository.search('canal');
        expect(results.map((c) => c.ref.key), ['b']);
      },
    );

    test('search respeta el límite', () async {
      await repository.importSourceContent(
        's1',
        Stream.fromIterable([
          for (var i = 0; i < 5; i++)
            sampleChannel(refKey: 'c$i', name: 'Canal $i'),
        ]),
        now: DateTime(2026, 1, 1),
      );

      final results = await repository.search('canal', limit: 2);
      expect(results, hasLength(2));
    });
  });

  group('DriftFavoritesRepository', () {
    late DriftFavoritesRepository repository;
    const channel = ChannelRef(sourceId: 's1', key: 'canal-1');

    setUp(() {
      repository = DriftFavoritesRepository(db);
    });

    test('upsert + find hace un round-trip', () async {
      final favorite = Favorite(
        channel: channel,
        order: 3,
        updatedAt: DateTime(2026, 1, 1),
      );
      await repository.upsert(favorite);

      expect(await repository.find(channel), favorite);
    });

    test('un tombstone sobrevive en la BD (no se borra la fila)', () async {
      final favorite = Favorite(
        channel: channel,
        updatedAt: DateTime(2026, 1, 1),
      );
      await repository.upsert(favorite);
      await repository.upsert(favorite.markDeleted(DateTime(2026, 1, 2)));

      final found = await repository.find(channel);
      expect(found, isNotNull);
      expect(found!.isDeleted, isTrue);
    });

    test('find devuelve null para un canal sin favorito', () async {
      expect(
        await repository.find(const ChannelRef(sourceId: 's1', key: 'x')),
        isNull,
      );
    });

    // S5 · Ola 2 (sección Favoritos, ui-spec §2.2/§2.3): el orden manual
    // es el punto de la pantalla — `getAll`/`watchAll` deben devolverlo en
    // ese orden, no en el orden físico de inserción de la tabla.
    test('getAll ordena por sortOrder, no por orden de inserción', () async {
      const a = ChannelRef(sourceId: 's1', key: 'a');
      const b = ChannelRef(sourceId: 's1', key: 'b');
      const c = ChannelRef(sourceId: 's1', key: 'c');
      // Se insertan fuera de orden a propósito.
      await repository.upsert(
        Favorite(channel: b, order: 1, updatedAt: DateTime(2026, 1, 1)),
      );
      await repository.upsert(
        Favorite(channel: c, order: 2, updatedAt: DateTime(2026, 1, 1)),
      );
      await repository.upsert(
        Favorite(channel: a, order: 0, updatedAt: DateTime(2026, 1, 1)),
      );

      final all = await repository.getAll();
      expect(all.map((f) => f.channel), [a, b, c]);
    });

    test(
      'ManageFavorites.reorder persiste el nuevo orden — un getAll '
      'posterior ya lo refleja',
      () async {
        const a = ChannelRef(sourceId: 's1', key: 'a');
        const b = ChannelRef(sourceId: 's1', key: 'b');
        const c = ChannelRef(sourceId: 's1', key: 'c');
        for (final (ref, order) in [(a, 0), (b, 1), (c, 2)]) {
          await repository.upsert(
            Favorite(channel: ref, order: order, updatedAt: DateTime(2026, 1, 1)),
          );
        }

        final manageFavorites = ManageFavorites(repository, const SystemClock());
        await manageFavorites.reorder([c, a, b]);

        final all = await repository.getAll();
        expect(all.map((f) => f.channel), [c, a, b]);
        expect(all.map((f) => f.order), [0, 1, 2]);
      },
    );
  });

  group('DriftWatchStateRepository', () {
    late DriftWatchStateRepository repository;
    const channel = ChannelRef(sourceId: 's1', key: 'canal-1');

    setUp(() {
      repository = DriftWatchStateRepository(db);
    });

    test('upsert + find conserva posición y duración', () async {
      final state = WatchState(
        channel: channel,
        position: const Duration(minutes: 12, seconds: 30),
        duration: const Duration(minutes: 45),
        updatedAt: DateTime(2026, 1, 1),
      );
      await repository.upsert(state);

      expect(await repository.find(channel), state);
    });
  });

  group('DriftPairedDeviceRepository', () {
    late DriftPairedDeviceRepository repository;

    setUp(() {
      repository = DriftPairedDeviceRepository(db);
    });

    test('upsert + find hace un round-trip', () async {
      final device = PairedDevice(
        deviceId: 'd1',
        name: 'LG Salón',
        platform: DevicePlatform.webos,
        publicKey: 'clave-publica',
        lastSeen: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      await repository.upsert(device);

      expect(await repository.find('d1'), device);
    });
  });
}
