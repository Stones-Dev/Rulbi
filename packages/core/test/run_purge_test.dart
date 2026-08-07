import 'dart:async';

import 'package:iptv_core/iptv_core.dart';
import 'package:test/test.dart';

/// Reloj falso para tests deterministas — mismo patrón que
/// `use_cases_test.dart` (nunca se compara contra `DateTime.now()` real).
final class _FakeClock implements Clock {
  _FakeClock(this._now);
  DateTime _now;

  @override
  DateTime now() => _now;

  void advance(Duration by) => _now = _now.add(by);
}

/// Fake de `EpgRepository`: solo interesa `purgeOutsideWindow` para estos
/// tests (`RunPurge` no llama a los otros dos métodos del puerto).
final class _FakeEpgRepository implements EpgRepository {
  int purgeCalls = 0;
  DateTime? lastFrom;
  DateTime? lastTo;
  int resultToReturn = 0;
  Object? errorToThrow;

  @override
  Future<int> purgeOutsideWindow({
    required DateTime from,
    required DateTime to,
  }) async {
    purgeCalls++;
    lastFrom = from;
    lastTo = to;
    if (errorToThrow != null) throw errorToThrow!;
    return resultToReturn;
  }

  @override
  Future<List<EpgProgramme>> programmesFor(
    String tvgId, {
    required DateTime from,
    required DateTime to,
  }) async => const [];

  @override
  Future<EpgNowIndex> nowAndNextFor(Set<String> tvgIds, DateTime at) async =>
      EpgNowIndex(at: at, entries: const {});
}

/// Variante que registra el orden de entrada/salida de
/// `purgeOutsideWindow` y queda bloqueada en la primera llamada hasta que
/// el test suelte `firstCallGate` — mismo patrón que
/// `_SequencedChannelRepository` de `use_cases_test.dart`, para probar
/// que dos `runOnce` concurrentes se serializan de verdad.
final class _SequencedEpgRepository implements EpgRepository {
  _SequencedEpgRepository({required this.order, required this.firstCallGate});

  final List<String> order;
  final Future<void> firstCallGate;
  int _calls = 0;

  @override
  Future<int> purgeOutsideWindow({
    required DateTime from,
    required DateTime to,
  }) async {
    final callNumber = ++_calls;
    order.add('start-$callNumber');
    if (callNumber == 1) await firstCallGate;
    order.add('end-$callNumber');
    return 0;
  }

  @override
  Future<List<EpgProgramme>> programmesFor(
    String tvgId, {
    required DateTime from,
    required DateTime to,
  }) async => const [];

  @override
  Future<EpgNowIndex> nowAndNextFor(Set<String> tvgIds, DateTime at) async =>
      EpgNowIndex(at: at, entries: const {});
}

/// Fake de `ChannelRepository`: solo interesa `purgeOrphanTombstones` —
/// los demás métodos no los usa `RunPurge`, mismo criterio de minimalismo
/// que `_FakeChannelRepository` de `use_cases_test.dart`.
final class _FakeChannelRepository implements ChannelRepository {
  int purgeCalls = 0;
  DateTime? lastDeletedBefore;
  int resultToReturn = 0;
  Object? errorToThrow;

  @override
  Future<int> purgeOrphanTombstones({required DateTime deletedBefore}) async {
    purgeCalls++;
    lastDeletedBefore = deletedBefore;
    if (errorToThrow != null) throw errorToThrow!;
    return resultToReturn;
  }

  @override
  Future<SourceImportStats> importSourceContent(
    String sourceId,
    Stream<Channel> channels, {
    required DateTime now,
  }) async {
    await channels.drain<void>();
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

/// Fake de `RunPurge` para los tests de `PurgeScheduler`: aísla al
/// scheduler de la lógica de ventanas/mutex de `DefaultRunPurge` (ya
/// cubierta en su propio grupo), solo cuenta invocaciones.
final class _FakeRunPurge implements RunPurge {
  int runOnceCalls = 0;
  int runIfDueCalls = 0;
  Object? errorToThrow;
  PurgeStats statsToReturn = PurgeStats(
    epgProgrammes: 0,
    channelTombstones: 0,
    ranAt: DateTime(2026, 1, 1),
  );

  @override
  Future<PurgeStats> runOnce() async {
    runOnceCalls++;
    if (errorToThrow != null) throw errorToThrow!;
    return statsToReturn;
  }

  @override
  Future<PurgeStats?> runIfDue() async {
    runIfDueCalls++;
    if (errorToThrow != null) throw errorToThrow!;
    return statsToReturn;
  }
}

void main() {
  group('DefaultRunPurge.runOnce', () {
    test(
      'deriva la ventana EPG y la gracia de tombstones desde Clock + '
      'PurgePolicy',
      () async {
        final epg = _FakeEpgRepository();
        final channels = _FakeChannelRepository();
        final clock = _FakeClock(DateTime(2026, 3, 10));
        final runPurge = DefaultRunPurge(
          epg,
          channels,
          clock,
          policy: const PurgePolicy(
            epgPast: Duration(days: 2),
            epgFuture: Duration(days: 5),
            tombstoneGrace: Duration(days: 15),
          ),
        );

        final stats = await runPurge.runOnce();

        expect(epg.lastFrom, DateTime(2026, 3, 8));
        expect(epg.lastTo, DateTime(2026, 3, 15));
        expect(channels.lastDeletedBefore, DateTime(2026, 2, 23));
        expect(stats.ranAt, clock.now());
      },
    );

    test('agrega lo borrado por cada puerto en PurgeStats', () async {
      final epg = _FakeEpgRepository()..resultToReturn = 42;
      final channels = _FakeChannelRepository()..resultToReturn = 7;
      final runPurge = DefaultRunPurge(
        epg,
        channels,
        _FakeClock(DateTime(2026, 1, 1)),
      );

      final stats = await runPurge.runOnce();

      expect(stats.epgProgrammes, 42);
      expect(stats.channelTombstones, 7);
    });

    test(
      'si la purga EPG falla, la de tombstones se intenta igual (y '
      'viceversa) — un job roto no debe impedir al otro',
      () async {
        final epg = _FakeEpgRepository()..errorToThrow = StateError('epg boom');
        final channels = _FakeChannelRepository()..resultToReturn = 7;
        final runPurge = DefaultRunPurge(
          epg,
          channels,
          _FakeClock(DateTime(2026, 1, 1)),
        );

        await expectLater(runPurge.runOnce, throwsStateError);

        expect(
          channels.purgeCalls,
          1,
          reason: 'la purga de tombstones debió intentarse igual',
        );
      },
    );

    test('dos runOnce concurrentes se serializan (mutex-por-future)', () async {
      final gate = Completer<void>();
      final order = <String>[];
      final epg = _SequencedEpgRepository(order: order, firstCallGate: gate.future);
      final channels = _FakeChannelRepository();
      final runPurge = DefaultRunPurge(
        epg,
        channels,
        _FakeClock(DateTime(2026, 1, 1)),
      );

      final first = runPurge.runOnce();
      // Deja que el primero entre en purgeOutsideWindow y quede bloqueado
      // en la puerta antes de lanzar el segundo.
      await Future<void>.delayed(Duration.zero);
      final second = runPurge.runOnce();
      await Future<void>.delayed(Duration.zero);

      expect(order, ['start-1']);

      gate.complete();
      await Future.wait([first, second]);

      expect(order, ['start-1', 'end-1', 'start-2', 'end-2']);
    });
  });

  group('DefaultRunPurge.runIfDue', () {
    test(
      'no corre si no ha pasado minInterval desde la última corrida',
      () async {
        final epg = _FakeEpgRepository();
        final channels = _FakeChannelRepository();
        final clock = _FakeClock(DateTime(2026, 1, 1));
        final runPurge = DefaultRunPurge(
          epg,
          channels,
          clock,
          policy: const PurgePolicy(minInterval: Duration(hours: 6)),
        );

        final first = await runPurge.runIfDue();
        expect(first, isNotNull);

        clock.advance(const Duration(hours: 1));
        final second = await runPurge.runIfDue();
        expect(second, isNull);
        expect(epg.purgeCalls, 1);
      },
    );

    test('corre de nuevo pasado minInterval', () async {
      final epg = _FakeEpgRepository();
      final channels = _FakeChannelRepository();
      final clock = _FakeClock(DateTime(2026, 1, 1));
      final runPurge = DefaultRunPurge(
        epg,
        channels,
        clock,
        policy: const PurgePolicy(minInterval: Duration(hours: 6)),
      );

      final first = await runPurge.runIfDue();
      expect(first, isNotNull);

      clock.advance(const Duration(hours: 6));
      final second = await runPurge.runIfDue();
      expect(second, isNotNull);
      expect(epg.purgeCalls, 2);
    });
  });

  group('PurgeScheduler', () {
    test(
      'start corre una vez al arrancar y una vez por cada tick del stream '
      'inyectado — sin Timer real',
      () async {
        final runPurge = _FakeRunPurge();
        final controller = StreamController<void>();
        addTearDown(controller.close);
        final scheduler = PurgeScheduler(runPurge, controller.stream);

        await scheduler.start();
        expect(runPurge.runIfDueCalls, 1);

        controller.add(null);
        await Future<void>.delayed(Duration.zero);
        expect(runPurge.runIfDueCalls, 2);

        controller.add(null);
        await Future<void>.delayed(Duration.zero);
        expect(runPurge.runIfDueCalls, 3);

        await scheduler.stop();
      },
    );

    test(
      'un fallo en runIfDue se reporta por onError y no detiene el '
      'scheduler',
      () async {
        final runPurge = _FakeRunPurge()..errorToThrow = StateError('boom');
        final controller = StreamController<void>();
        addTearDown(controller.close);
        final errors = <Object>[];
        final scheduler = PurgeScheduler(
          runPurge,
          controller.stream,
          onError: (error, stackTrace) => errors.add(error),
        );

        await scheduler.start();
        expect(errors, hasLength(1));

        controller.add(null);
        await Future<void>.delayed(Duration.zero);
        expect(errors, hasLength(2));
        expect(runPurge.runIfDueCalls, 2);

        await scheduler.stop();
      },
    );

    test('stop deja de escuchar el stream de triggers', () async {
      final runPurge = _FakeRunPurge();
      final controller = StreamController<void>();
      addTearDown(controller.close);
      final scheduler = PurgeScheduler(runPurge, controller.stream);

      await scheduler.start();
      expect(runPurge.runIfDueCalls, 1);
      await scheduler.stop();

      controller.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(runPurge.runIfDueCalls, 1);
    });
  });

  group('PurgeStats', () {
    test('round-trip toJson -> fromJson -> toJson es estable', () {
      final stats = PurgeStats(
        epgProgrammes: 120,
        channelTombstones: 8,
        ranAt: DateTime.utc(2026, 3, 10, 4),
      );

      final json = stats.toJson();
      final roundTripped = PurgeStats.fromJson(json);

      expect(roundTripped, stats);
      expect(roundTripped.toJson(), json);
    });
  });
}
