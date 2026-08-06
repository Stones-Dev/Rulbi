import 'dart:async';

import 'package:iptv_core/iptv_core.dart';
import 'package:test/test.dart';

/// Reloj falso para tests deterministas: nunca se debe comparar contra
/// `DateTime.now()` real (ver `Clock`).
final class _FakeClock implements Clock {
  _FakeClock(this._now);
  DateTime _now;

  @override
  DateTime now() => _now;

  void advance(Duration by) => _now = _now.add(by);
}

final class _InMemoryFavoritesRepository implements FavoritesRepository {
  final Map<ChannelRef, Favorite> _byChannel = {};

  @override
  Future<List<Favorite>> getAll() async => _byChannel.values.toList();

  @override
  Future<Favorite?> find(ChannelRef channel) async => _byChannel[channel];

  @override
  Future<void> upsert(Favorite favorite) async {
    _byChannel[favorite.channel] = favorite;
  }

  @override
  Stream<List<Favorite>> watchAll() => Stream.value(_byChannel.values.toList());
}

final class _InMemoryWatchStateRepository implements WatchStateRepository {
  final Map<ChannelRef, WatchState> _byChannel = {};

  @override
  Future<List<WatchState>> getAll() async => _byChannel.values.toList();

  @override
  Future<WatchState?> find(ChannelRef channel) async => _byChannel[channel];

  @override
  Future<void> upsert(WatchState state) async {
    _byChannel[state.channel] = state;
  }
}

final class _InMemorySourceRepository implements SourceRepository {
  final Map<String, Source> _byId = {};

  @override
  Future<List<Source>> getAll() async => _byId.values.toList();

  @override
  Future<Source?> getById(String id) async => _byId[id];

  @override
  Future<void> upsert(Source source) async => _byId[source.id] = source;

  @override
  Stream<List<Source>> watchAll() => Stream.value(_byId.values.toList());
}

/// Fake de `ChannelRepository` para `DefaultManageSources`: no hace ningún
/// diff real (eso se prueba en `data`, contra SQLite de verdad), solo
/// registra cómo se le llamó y devuelve un [SourceImportStats] fijado por
/// el test — lo que interesa aquí es que la orquestación delegue y no
/// reinterprete.
final class _FakeChannelRepository implements ChannelRepository {
  int importCalls = 0;
  String? lastSourceId;
  DateTime? lastNow;
  SourceImportStats statsToReturn = const SourceImportStats(
    inserted: 0,
    updated: 0,
    unchanged: 0,
    tombstoned: 0,
    resurrected: 0,
    duplicateRefs: 0,
  );

  @override
  Future<SourceImportStats> importSourceContent(
    String sourceId,
    Stream<Channel> channels, {
    required DateTime now,
  }) async {
    importCalls++;
    lastSourceId = sourceId;
    lastNow = now;
    await channels.drain<void>();
    return statsToReturn;
  }

  @override
  Future<List<Category>> categoriesFor(String sourceId) async => const [];

  @override
  Stream<List<Channel>> watchChannels({required String categoryId}) =>
      const Stream.empty();

  @override
  Future<int> countBySource(String sourceId) async => 0;

  @override
  Future<int> purgeOrphanTombstones({required DateTime deletedBefore}) async =>
      0;

  @override
  Future<int> countChannels(ChannelQuery query) async => 0;

  @override
  Future<List<Channel>> channelsPage(
    ChannelQuery query, {
    required int offset,
    required int limit,
  }) async => const [];

  @override
  Future<List<CategoryWithCount>> categoriesWithCount(
    ChannelQuery query,
  ) async => const [];

  @override
  Future<List<Channel>> findByRefs(List<ChannelRef> refs) async => const [];
}

/// Variante que registra el orden de entrada/salida de
/// [importSourceContent] y deja bloqueada la primera llamada hasta que el
/// test suelte [firstCallGate] — para probar que dos imports concurrentes
/// de la misma fuente se serializan de verdad, no solo "no truenan".
final class _SequencedChannelRepository implements ChannelRepository {
  _SequencedChannelRepository({required this.order, required this.firstCallGate});

  final List<String> order;
  final Future<void> firstCallGate;
  int _calls = 0;

  @override
  Future<SourceImportStats> importSourceContent(
    String sourceId,
    Stream<Channel> channels, {
    required DateTime now,
  }) async {
    final callNumber = ++_calls;
    order.add('start-$callNumber');
    if (callNumber == 1) {
      await firstCallGate;
    }
    order.add('end-$callNumber');
    return const SourceImportStats(
      inserted: 0,
      updated: 0,
      unchanged: 0,
      tombstoned: 0,
      resurrected: 0,
      duplicateRefs: 0,
    );
  }

  @override
  Future<List<Category>> categoriesFor(String sourceId) async => const [];

  @override
  Stream<List<Channel>> watchChannels({required String categoryId}) =>
      const Stream.empty();

  @override
  Future<int> countBySource(String sourceId) async => 0;

  @override
  Future<int> purgeOrphanTombstones({required DateTime deletedBefore}) async =>
      0;

  @override
  Future<int> countChannels(ChannelQuery query) async => 0;

  @override
  Future<List<Channel>> channelsPage(
    ChannelQuery query, {
    required int offset,
    required int limit,
  }) async => const [];

  @override
  Future<List<CategoryWithCount>> categoriesWithCount(
    ChannelQuery query,
  ) async => const [];

  @override
  Future<List<Channel>> findByRefs(List<ChannelRef> refs) async => const [];
}

final class _FakeChannelSearchPort implements ChannelSearchPort {
  List<Channel> results = const [];
  String? lastQuery;
  ContentType? lastType;
  Set<String>? lastSourceIds;

  /// Resultados por tipo para `SearchChannels.grouped` — si no se fija,
  /// [search] cae a filtrar [results] por [ContentType] a mano, que es
  /// suficiente para no repetir la lista tres veces en los tests simples.
  Map<ContentType, List<Channel>>? resultsByType;

  @override
  Future<List<Channel>> search(
    String query, {
    ContentType? type,
    Set<String>? sourceIds,
    int limit = 50,
  }) async {
    lastQuery = query;
    lastType = type;
    lastSourceIds = sourceIds;
    final byType = resultsByType;
    final source = byType != null
        ? (type == null
              ? byType.values.expand((c) => c).toList()
              : (byType[type] ?? const []))
        : (type == null
              ? results
              : results.where((c) => c.type == type).toList());
    return source.take(limit).toList();
  }
}

/// Fake de `ChannelRepository` para `GetContinueWatching`: solo
/// `findByRefs` tiene comportamiento real (busca en un `Map` por
/// `ChannelRef`, un ref ausente simplemente no aparece — mismo contrato
/// que la implementación de `data`); el resto de la interfaz no participa
/// en este caso de uso.
final class _InMemoryChannelStore implements ChannelRepository {
  final Map<ChannelRef, Channel> _byRef = {};

  void seed(Channel channel) => _byRef[channel.ref] = channel;

  @override
  Future<List<Channel>> findByRefs(List<ChannelRef> refs) async =>
      [for (final ref in refs) ?_byRef[ref]];

  @override
  Future<SourceImportStats> importSourceContent(
    String sourceId,
    Stream<Channel> channels, {
    required DateTime now,
  }) => throw UnimplementedError();

  @override
  Future<List<Category>> categoriesFor(String sourceId) async => const [];

  @override
  Stream<List<Channel>> watchChannels({required String categoryId}) =>
      const Stream.empty();

  @override
  Future<int> countBySource(String sourceId) async => 0;

  @override
  Future<int> purgeOrphanTombstones({required DateTime deletedBefore}) async =>
      0;

  @override
  Future<int> countChannels(ChannelQuery query) async => 0;

  @override
  Future<List<Channel>> channelsPage(
    ChannelQuery query, {
    required int offset,
    required int limit,
  }) async => const [];

  @override
  Future<List<CategoryWithCount>> categoriesWithCount(
    ChannelQuery query,
  ) async => const [];
}

void main() {
  group('ManageFavorites', () {
    late _InMemoryFavoritesRepository repository;
    late _FakeClock clock;
    late ManageFavorites useCase;
    const channel = ChannelRef(sourceId: 's1', key: 'canal-1');

    setUp(() {
      repository = _InMemoryFavoritesRepository();
      clock = _FakeClock(DateTime(2026, 1, 1));
      useCase = ManageFavorites(repository, clock);
    });

    test('toggle marca como favorito un canal que no lo era', () async {
      await useCase.toggle(channel);
      final favorite = await repository.find(channel);
      expect(favorite, isNotNull);
      expect(favorite!.isDeleted, isFalse);
    });

    test(
      'toggle sobre un favorito existente lo tumba (tombstone), no lo borra',
      () async {
        await useCase.toggle(channel);
        clock.advance(const Duration(minutes: 1));
        await useCase.toggle(channel);

        final favorite = await repository.find(channel);
        expect(
          favorite,
          isNotNull,
          reason: 'el registro debe seguir existiendo',
        );
        expect(favorite!.isDeleted, isTrue);
      },
    );

    test('toggle sobre un favorito ya tumbado lo revive', () async {
      await useCase.toggle(channel);
      clock.advance(const Duration(minutes: 1));
      await useCase.toggle(channel);
      clock.advance(const Duration(minutes: 1));
      await useCase.toggle(channel);

      final favorite = await repository.find(channel);
      expect(favorite!.isDeleted, isFalse);
    });

    test(
      'reorder solo toca los favoritos vivos presentes en la lista',
      () async {
        const a = ChannelRef(sourceId: 's1', key: 'a');
        const b = ChannelRef(sourceId: 's1', key: 'b');
        await useCase.toggle(a);
        await useCase.toggle(b);

        await useCase.reorder([b, a]);

        expect((await repository.find(b))!.order, 0);
        expect((await repository.find(a))!.order, 1);
      },
    );
  });

  group('TrackWatchProgress', () {
    late _InMemoryWatchStateRepository repository;
    late _FakeClock clock;
    late TrackWatchProgress useCase;
    const channel = ChannelRef(sourceId: 's1', key: 'canal-1');

    setUp(() {
      repository = _InMemoryWatchStateRepository();
      clock = _FakeClock(DateTime(2026, 1, 1));
      useCase = TrackWatchProgress(repository, clock);
    });

    test(
      'updateProgress persiste posición/duración con el reloj inyectado',
      () async {
        await useCase.updateProgress(
          channel,
          position: const Duration(minutes: 10),
          duration: const Duration(minutes: 100),
        );
        final state = await repository.find(channel);
        expect(state!.updatedAt, clock.now());
        expect(state.fraction, closeTo(0.1, 0.0001));
      },
    );

    test(
      'continueWatching excluye lo terminado y lo que no ha empezado',
      () async {
        const started = ChannelRef(sourceId: 's1', key: 'started');
        const finished = ChannelRef(sourceId: 's1', key: 'finished');
        const notStarted = ChannelRef(sourceId: 's1', key: 'not-started');

        await useCase.updateProgress(
          started,
          position: const Duration(minutes: 10),
          duration: const Duration(minutes: 100),
        );
        await useCase.updateProgress(
          finished,
          position: const Duration(minutes: 99),
          duration: const Duration(minutes: 100),
        );
        await useCase.updateProgress(
          notStarted,
          position: Duration.zero,
          duration: const Duration(minutes: 100),
        );

        final result = await useCase.continueWatching();
        expect(result.map((w) => w.channel), [started]);
      },
    );

    test('continueWatching devuelve lo más reciente primero', () async {
      const first = ChannelRef(sourceId: 's1', key: 'first');
      const second = ChannelRef(sourceId: 's1', key: 'second');

      await useCase.updateProgress(
        first,
        position: const Duration(minutes: 1),
        duration: const Duration(minutes: 100),
      );
      clock.advance(const Duration(minutes: 1));
      await useCase.updateProgress(
        second,
        position: const Duration(minutes: 1),
        duration: const Duration(minutes: 100),
      );

      final result = await useCase.continueWatching();
      expect(result.map((w) => w.channel), [second, first]);
    });
  });

  group('DefaultManageSources', () {
    Source sampleSource({
      String id = 's1',
      String name = 'Mi lista',
      DateTime? updatedAt,
      DateTime? deletedAt,
    }) => Source(
      id: id,
      name: name,
      config: const M3uFileSourceConfig(filePath: '/tmp/a.m3u'),
      updatedAt: updatedAt ?? DateTime(2020, 1, 1),
      deletedAt: deletedAt,
    );

    test('addSource persiste el Source y deja lastRefresh en clock.now()', () async {
      final sources = _InMemorySourceRepository();
      final channels = _FakeChannelRepository();
      final clock = _FakeClock(DateTime(2026, 1, 1));
      final useCase = DefaultManageSources(sources, channels, clock);

      final (persisted, _) = await useCase.addSource(
        sampleSource(),
        const Stream.empty(),
      );

      expect(persisted.lastRefresh, clock.now());
      expect((await sources.getById('s1'))!.lastRefresh, clock.now());
    });

    test(
      'addSource delega el diff en el puerto una sola vez y devuelve sus '
      'stats sin reinterpretarlas',
      () async {
        final sources = _InMemorySourceRepository();
        final channels = _FakeChannelRepository()
          ..statsToReturn = const SourceImportStats(
            inserted: 3,
            updated: 1,
            unchanged: 2,
            tombstoned: 0,
            resurrected: 0,
            duplicateRefs: 1,
          );
        final useCase = DefaultManageSources(
          sources,
          channels,
          _FakeClock(DateTime(2026, 1, 1)),
        );

        final (_, stats) = await useCase.addSource(
          sampleSource(),
          const Stream.empty(),
        );

        expect(channels.importCalls, 1);
        expect(channels.lastSourceId, 's1');
        expect(stats, channels.statsToReturn);
      },
    );

    test('refreshSource sobre un sourceId inexistente falla sin escribir nada', () async {
      final sources = _InMemorySourceRepository();
      final channels = _FakeChannelRepository();
      final useCase = DefaultManageSources(
        sources,
        channels,
        _FakeClock(DateTime(2026, 1, 1)),
      );

      await expectLater(
        () => useCase.refreshSource('no-existe', const Stream.empty()),
        throwsStateError,
      );
      expect(channels.importCalls, 0);
      expect(await sources.getAll(), isEmpty);
    });

    test('refreshSource sobre una fuente eliminada falla', () async {
      final sources = _InMemorySourceRepository();
      await sources.upsert(
        sampleSource(deletedAt: DateTime(2026, 1, 2)),
      );
      final channels = _FakeChannelRepository();
      final useCase = DefaultManageSources(
        sources,
        channels,
        _FakeClock(DateTime(2026, 1, 3)),
      );

      await expectLater(
        () => useCase.refreshSource('s1', const Stream.empty()),
        throwsStateError,
      );
      expect(channels.importCalls, 0);
    });

    test(
      'dos refreshSource concurrentes sobre el mismo sourceId se serializan',
      () async {
        final sources = _InMemorySourceRepository();
        await sources.upsert(sampleSource());

        final gate = Completer<void>();
        final order = <String>[];
        final channels = _SequencedChannelRepository(
          order: order,
          firstCallGate: gate.future,
        );
        final useCase = DefaultManageSources(
          sources,
          channels,
          _FakeClock(DateTime(2026, 1, 1)),
        );

        final first = useCase.refreshSource('s1', const Stream.empty());
        // Deja que el primero entre en importSourceContent y quede
        // bloqueado en la puerta antes de lanzar el segundo.
        await Future<void>.delayed(Duration.zero);
        final second = useCase.refreshSource('s1', const Stream.empty());
        await Future<void>.delayed(Duration.zero);

        // El segundo no debe haber arrancado todavía: sigue encolado
        // detrás del primero, que sigue bloqueado en la puerta.
        expect(order, ['start-1']);

        gate.complete();
        await Future.wait([first, second]);

        expect(order, ['start-1', 'end-1', 'start-2', 'end-2']);
      },
    );
  });

  group('SourceImportStats.toJson (T1.9)', () {
    test('serializa las 6 cuentas con claves en orden fijo', () {
      const stats = SourceImportStats(
        inserted: 128,
        updated: 12,
        unchanged: 13420,
        tombstoned: 3,
        resurrected: 1,
        duplicateRefs: 2,
      );

      expect(stats.toJson(), {
        'inserted': 128,
        'updated': 12,
        'unchanged': 13420,
        'tombstoned': 3,
        'resurrected': 1,
        'duplicateRefs': 2,
      });
    });

    test('round-trip toJson -> fromJson -> toJson es estable', () {
      const stats = SourceImportStats(
        inserted: 128,
        updated: 12,
        unchanged: 13420,
        tombstoned: 3,
        resurrected: 1,
        duplicateRefs: 2,
      );

      final json = stats.toJson();
      final roundTripped = SourceImportStats.fromJson(json);

      expect(roundTripped, stats);
      expect(roundTripped.toJson(), json);
    });
  });

  group('SearchChannels', () {
    test('no llama al puerto con una consulta vacía o solo espacios', () async {
      final port = _FakeChannelSearchPort();
      final useCase = SearchChannels(port);

      final result = await useCase('   ');

      expect(result, isEmpty);
      expect(port.lastQuery, isNull);
    });

    test('recorta la consulta antes de delegar en el puerto', () async {
      final port = _FakeChannelSearchPort();
      final useCase = SearchChannels(port);

      await useCase('  españa  ');

      expect(port.lastQuery, 'españa');
    });

    group('grouped (ui-spec §2.11)', () {
      Channel channelOf(ContentType type, String name) => Channel(
        ref: ChannelRef(sourceId: 's1', key: name),
        sourceId: 's1',
        type: type,
        name: name,
        url: Uri.parse('http://example.com/$name'),
      );

      test('consulta vacía no llama al puerto y devuelve tres grupos vacíos', () async {
        final port = _FakeChannelSearchPort();
        final useCase = SearchChannels(port);

        final result = await useCase.grouped('   ');

        expect(result.isEmpty, isTrue);
        expect(port.lastQuery, isNull);
      });

      test('reparte los resultados en directo/vod/series por tipo', () async {
        final port = _FakeChannelSearchPort()
          ..resultsByType = {
            ContentType.live: [channelOf(ContentType.live, 'La 1')],
            ContentType.vod: [channelOf(ContentType.vod, 'La 1: la película')],
            ContentType.series: <Channel>[],
          };
        final useCase = SearchChannels(port);

        final result = await useCase.grouped('la 1');

        expect(result.live.map((c) => c.name), ['La 1']);
        expect(result.vod.map((c) => c.name), ['La 1: la película']);
        expect(result.series, isEmpty);
      });

      test('un tipo con muchos aciertos no roba el límite de los otros', () async {
        final port = _FakeChannelSearchPort()
          ..resultsByType = {
            ContentType.live: List.generate(
              50,
              (i) => channelOf(ContentType.live, 'canal-$i'),
            ),
            ContentType.vod: [channelOf(ContentType.vod, 'peli-1')],
            ContentType.series: <Channel>[],
          };
        final useCase = SearchChannels(port);

        final result = await useCase.grouped('canal', limitPerType: 20);

        expect(result.live, hasLength(20));
        expect(result.vod, hasLength(1));
      });

      test('pasa sourceIds al puerto en las tres llamadas', () async {
        final port = _FakeChannelSearchPort();
        final useCase = SearchChannels(port);

        await useCase.grouped('la 1', sourceIds: {'s1', 's2'});

        expect(port.lastSourceIds, {'s1', 's2'});
      });
    });
  });

  group('GetContinueWatching (ui-spec §2.2, S5 · Ola 1)', () {
    late _InMemoryWatchStateRepository watchStateRepository;
    late _InMemoryChannelStore channels;
    late _FakeClock clock;
    late TrackWatchProgress trackWatchProgress;
    late GetContinueWatching useCase;

    setUp(() {
      watchStateRepository = _InMemoryWatchStateRepository();
      channels = _InMemoryChannelStore();
      clock = _FakeClock(DateTime(2026, 1, 1));
      trackWatchProgress = TrackWatchProgress(watchStateRepository, clock);
      useCase = GetContinueWatching(trackWatchProgress, channels);
    });

    test('hidrata cada ref con su canal completo', () async {
      const ref = ChannelRef(sourceId: 's1', key: 'canal-1');
      channels.seed(
        Channel(
          ref: ref,
          sourceId: 's1',
          type: ContentType.vod,
          name: 'Oppenheimer',
          url: Uri.parse('http://example.com/oppenheimer'),
        ),
      );
      await trackWatchProgress.updateProgress(
        ref,
        position: const Duration(minutes: 30),
        duration: const Duration(minutes: 120),
      );

      final result = await useCase();

      expect(result, hasLength(1));
      expect(result.single.channel.name, 'Oppenheimer');
      expect(result.single.fraction, closeTo(0.25, 0.0001));
    });

    test('descarta refs cuyo canal ya no existe (fuente borrada)', () async {
      const gone = ChannelRef(sourceId: 's1', key: 'ya-no-existe');
      // Nunca sembrado en `channels`: simula una fuente eliminada tras
      // guardarse el progreso.
      await trackWatchProgress.updateProgress(
        gone,
        position: const Duration(minutes: 5),
        duration: const Duration(minutes: 50),
      );

      final result = await useCase();

      expect(result, isEmpty);
    });

    test('preserva el orden de continueWatching (más reciente primero)', () async {
      const first = ChannelRef(sourceId: 's1', key: 'first');
      const second = ChannelRef(sourceId: 's1', key: 'second');
      for (final ref in [first, second]) {
        channels.seed(
          Channel(
            ref: ref,
            sourceId: 's1',
            type: ContentType.vod,
            name: ref.key,
            url: Uri.parse('http://example.com/${ref.key}'),
          ),
        );
      }
      await trackWatchProgress.updateProgress(
        first,
        position: const Duration(minutes: 1),
        duration: const Duration(minutes: 100),
      );
      clock.advance(const Duration(minutes: 1));
      await trackWatchProgress.updateProgress(
        second,
        position: const Duration(minutes: 1),
        duration: const Duration(minutes: 100),
      );

      final result = await useCase();

      expect(result.map((i) => i.channel.name), ['second', 'first']);
    });

    test('respeta el límite pedido', () async {
      for (var i = 0; i < 5; i++) {
        final ref = ChannelRef(sourceId: 's1', key: 'canal-$i');
        channels.seed(
          Channel(
            ref: ref,
            sourceId: 's1',
            type: ContentType.vod,
            name: 'canal-$i',
            url: Uri.parse('http://example.com/canal-$i'),
          ),
        );
        await trackWatchProgress.updateProgress(
          ref,
          position: const Duration(minutes: 1),
          duration: const Duration(minutes: 100),
        );
      }

      final result = await useCase(limit: 2);

      expect(result, hasLength(2));
    });

    test('un ítem en directo (duration cero) se incluye con fraction 0', () async {
      const ref = ChannelRef(sourceId: 's1', key: 'directo');
      channels.seed(
        Channel(
          ref: ref,
          sourceId: 's1',
          type: ContentType.live,
          name: 'DAZN 1',
          url: Uri.parse('http://example.com/dazn1'),
        ),
      );
      await trackWatchProgress.updateProgress(
        ref,
        position: const Duration(minutes: 5),
        duration: Duration.zero,
      );

      final result = await useCase();

      expect(result, hasLength(1));
      expect(result.single.fraction, 0);
    });
  });
}
