import 'dart:async';

import 'package:iptv_core/iptv_core.dart';
import 'package:test/test.dart';

/// Reloj falso para tests deterministas — mismo patrón que
/// `run_purge_test.dart`/`use_cases_test.dart` (nunca se compara contra
/// `DateTime.now()` real).
final class _FakeClock implements Clock {
  _FakeClock(this._now);
  DateTime _now;

  @override
  DateTime now() => _now;

  void advance(Duration by) => _now = _now.add(by);
}

Source _source(
  String id, {
  bool enabled = true,
  DateTime? deletedAt,
  DateTime? updatedAt,
}) => Source(
  id: id,
  config: M3uUrlSourceConfig(url: Uri.parse('http://example.com/$id.m3u')),
  name: 'Fuente $id',
  enabled: enabled,
  updatedAt: updatedAt ?? DateTime(2026, 1, 1),
  deletedAt: deletedAt,
);

/// Fake de `SourceRepository`: solo `getAll` importa a `RunEpgRefresh`
/// (itera todas las fuentes, filtra tumbadas/desactivadas él mismo — ver
/// docstring de `DefaultRunEpgRefresh._runOnceLocked`).
final class _FakeSourceRepository implements SourceRepository {
  final List<Source> sources = [];

  @override
  Future<List<Source>> getAll() async => List.unmodifiable(sources);

  @override
  Future<Source?> getById(String id) async {
    for (final source in sources) {
      if (source.id == id) return source;
    }
    return null;
  }

  @override
  Future<void> upsert(Source source) async {
    sources.removeWhere((s) => s.id == source.id);
    sources.add(source);
  }

  @override
  Stream<List<Source>> watchAll() => Stream.value(List.unmodifiable(sources));
}

/// Fake de `EpgIngestPort`: resultado/error configurable por `sourceId`,
/// registra el orden de llamadas.
final class _FakeEpgIngestPort implements EpgIngestPort {
  final List<String> callsBySourceId = [];
  final Map<String, EpgImportStats?> statsBySourceId = {};
  final Map<String, Object> errorsBySourceId = {};

  @override
  Future<EpgImportStats?> ingestFor(Source source, {required DateTime now}) async {
    callsBySourceId.add(source.id);
    final error = errorsBySourceId[source.id];
    if (error != null) throw error;
    return statsBySourceId[source.id];
  }
}

EpgImportStats _stats({int inserted = 0, int updated = 0}) => EpgImportStats(
  programmesInserted: inserted,
  programmesUpdated: updated,
  programmesUnchanged: 0,
  channelsInserted: 0,
  channelsUpdated: 0,
  channelsUnchanged: 0,
  duplicateKeys: 0,
);

/// Fake de `RunEpgRefresh` para los tests de `PeriodicJobScheduler`: aísla
/// al scheduler de la lógica de fuentes/mutex de `DefaultRunEpgRefresh`
/// (ya cubierta en su propio grupo), solo cuenta invocaciones — mismo
/// criterio que `_FakeRunPurge` de `run_purge_test.dart`.
final class _FakeRunEpgRefresh implements RunEpgRefresh {
  int runOnceCalls = 0;
  int runIfDueCalls = 0;
  Object? errorToThrow;
  EpgRefreshStats statsToReturn = EpgRefreshStats(
    sourcesRefreshed: 0,
    sourcesSkipped: 0,
    sourcesFailed: 0,
    programmesWritten: 0,
    ranAt: DateTime(2026, 1, 1),
  );

  @override
  Future<EpgRefreshStats> runOnce() async {
    runOnceCalls++;
    if (errorToThrow != null) throw errorToThrow!;
    return statsToReturn;
  }

  @override
  Future<EpgRefreshStats?> runIfDue() async {
    runIfDueCalls++;
    if (errorToThrow != null) throw errorToThrow!;
    return statsToReturn;
  }
}

void main() {
  group('DefaultRunEpgRefresh.runOnce', () {
    test('refresca cada fuente viva y activa, agregando programmesWritten', () async {
      final sources = _FakeSourceRepository()
        ..sources.addAll([_source('a'), _source('b')]);
      final ingest = _FakeEpgIngestPort()
        ..statsBySourceId['a'] = _stats(inserted: 10, updated: 2)
        ..statsBySourceId['b'] = _stats(inserted: 3, updated: 0);
      final refresh = DefaultRunEpgRefresh(sources, ingest, _FakeClock(DateTime(2026, 3, 10)));

      final stats = await refresh.runOnce();

      expect(stats.sourcesRefreshed, 2);
      expect(stats.sourcesSkipped, 0);
      expect(stats.sourcesFailed, 0);
      expect(stats.programmesWritten, 15);
      expect(ingest.callsBySourceId, unorderedEquals(['a', 'b']));
    });

    test('salta fuentes desactivadas, sin llamar a ingestFor', () async {
      final sources = _FakeSourceRepository()
        ..sources.addAll([_source('a', enabled: false), _source('b')]);
      final ingest = _FakeEpgIngestPort()..statsBySourceId['b'] = _stats(inserted: 1);
      final refresh = DefaultRunEpgRefresh(sources, ingest, _FakeClock(DateTime(2026, 3, 10)));

      final stats = await refresh.runOnce();

      expect(stats.sourcesSkipped, 1);
      expect(stats.sourcesRefreshed, 1);
      expect(ingest.callsBySourceId, ['b']);
    });

    test('salta fuentes tumbadas (deletedAt no nulo), sin llamar a ingestFor', () async {
      final sources = _FakeSourceRepository()
        ..sources.addAll([_source('a', deletedAt: DateTime(2026, 2, 1)), _source('b')]);
      final ingest = _FakeEpgIngestPort()..statsBySourceId['b'] = _stats(inserted: 1);
      final refresh = DefaultRunEpgRefresh(sources, ingest, _FakeClock(DateTime(2026, 3, 10)));

      final stats = await refresh.runOnce();

      expect(stats.sourcesSkipped, 1);
      expect(ingest.callsBySourceId, ['b']);
    });

    test('una fuente sin guía (ingestFor -> null) cuenta como saltada, no como fallida', () async {
      final sources = _FakeSourceRepository()..sources.add(_source('a'));
      final ingest = _FakeEpgIngestPort(); // sin entrada en statsBySourceId -> null
      final refresh = DefaultRunEpgRefresh(sources, ingest, _FakeClock(DateTime(2026, 3, 10)));

      final stats = await refresh.runOnce();

      expect(stats.sourcesSkipped, 1);
      expect(stats.sourcesRefreshed, 0);
      expect(stats.sourcesFailed, 0);
    });

    test(
      'una fuente que falla no impide refrescar las demás — se cuenta, no se relanza',
      () async {
        final sources = _FakeSourceRepository()
          ..sources.addAll([_source('a'), _source('b'), _source('c')]);
        final ingest = _FakeEpgIngestPort()
          ..errorsBySourceId['a'] = StateError('panel caído')
          ..statsBySourceId['b'] = _stats(inserted: 5)
          ..statsBySourceId['c'] = _stats(inserted: 1);
        final refresh = DefaultRunEpgRefresh(sources, ingest, _FakeClock(DateTime(2026, 3, 10)));

        final stats = await refresh.runOnce();

        expect(stats.sourcesFailed, 1);
        expect(stats.sourcesRefreshed, 2);
        expect(stats.programmesWritten, 6);
        expect(ingest.callsBySourceId, unorderedEquals(['a', 'b', 'c']));
      },
    );

    test('dos runOnce concurrentes se serializan (mutex-por-future)', () async {
      final gate = Completer<void>();
      final order = <String>[];
      final sources = _FakeSourceRepository()..sources.add(_source('a'));
      final ingest = _SequencedEpgIngestPort(order: order, firstCallGate: gate.future);
      final refresh = DefaultRunEpgRefresh(sources, ingest, _FakeClock(DateTime(2026, 1, 1)));

      final first = refresh.runOnce();
      await Future<void>.delayed(Duration.zero);
      final second = refresh.runOnce();
      await Future<void>.delayed(Duration.zero);

      expect(order, ['start-1']);

      gate.complete();
      await Future.wait([first, second]);

      expect(order, ['start-1', 'end-1', 'start-2', 'end-2']);
    });
  });

  group('DefaultRunEpgRefresh.runIfDue', () {
    test('no corre si no ha pasado minInterval desde la última corrida', () async {
      final sources = _FakeSourceRepository()..sources.add(_source('a'));
      final ingest = _FakeEpgIngestPort()..statsBySourceId['a'] = _stats(inserted: 1);
      final clock = _FakeClock(DateTime(2026, 1, 1));
      final refresh = DefaultRunEpgRefresh(
        sources,
        ingest,
        clock,
        policy: const EpgRefreshPolicy(minInterval: Duration(hours: 6)),
      );

      final first = await refresh.runIfDue();
      expect(first, isNotNull);

      clock.advance(const Duration(hours: 1));
      final second = await refresh.runIfDue();
      expect(second, isNull);
      expect(ingest.callsBySourceId, ['a']);
    });

    test('corre de nuevo pasado minInterval', () async {
      final sources = _FakeSourceRepository()..sources.add(_source('a'));
      final ingest = _FakeEpgIngestPort()..statsBySourceId['a'] = _stats(inserted: 1);
      final clock = _FakeClock(DateTime(2026, 1, 1));
      final refresh = DefaultRunEpgRefresh(
        sources,
        ingest,
        clock,
        policy: const EpgRefreshPolicy(minInterval: Duration(hours: 6)),
      );

      final first = await refresh.runIfDue();
      expect(first, isNotNull);

      clock.advance(const Duration(hours: 6));
      final second = await refresh.runIfDue();
      expect(second, isNotNull);
      expect(ingest.callsBySourceId, ['a', 'a']);
    });
  });

  group('PeriodicJobScheduler con RunEpgRefresh (S5.5, Bloque B3)', () {
    test(
      'start corre una vez al arrancar y una vez por cada tick del stream '
      'inyectado — sin Timer real',
      () async {
        final refresh = _FakeRunEpgRefresh();
        final controller = StreamController<void>();
        addTearDown(controller.close);
        final scheduler = PeriodicJobScheduler(refresh, controller.stream);

        await scheduler.start();
        expect(refresh.runIfDueCalls, 1);

        controller.add(null);
        await Future<void>.delayed(Duration.zero);
        expect(refresh.runIfDueCalls, 2);

        await scheduler.stop();
      },
    );

    test('un fallo en runIfDue se reporta por onError y no detiene el scheduler', () async {
      final refresh = _FakeRunEpgRefresh()..errorToThrow = StateError('boom');
      final controller = StreamController<void>();
      addTearDown(controller.close);
      final errors = <Object>[];
      final scheduler = PeriodicJobScheduler(
        refresh,
        controller.stream,
        onError: (error, stackTrace) => errors.add(error),
      );

      await scheduler.start();
      expect(errors, hasLength(1));

      controller.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(errors, hasLength(2));

      await scheduler.stop();
    });

    test('stop deja de escuchar el stream de triggers', () async {
      final refresh = _FakeRunEpgRefresh();
      final controller = StreamController<void>();
      addTearDown(controller.close);
      final scheduler = PeriodicJobScheduler(refresh, controller.stream);

      await scheduler.start();
      expect(refresh.runIfDueCalls, 1);
      await scheduler.stop();

      controller.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(refresh.runIfDueCalls, 1);
    });
  });

  group('EpgRefreshStats', () {
    test('round-trip toJson -> fromJson -> toJson es estable', () {
      final stats = EpgRefreshStats(
        sourcesRefreshed: 3,
        sourcesSkipped: 1,
        sourcesFailed: 1,
        programmesWritten: 240,
        ranAt: DateTime.utc(2026, 3, 10, 4),
      );

      final json = stats.toJson();
      final roundTripped = EpgRefreshStats.fromJson(json);

      expect(roundTripped, stats);
      expect(roundTripped.toJson(), json);
    });
  });
}

/// Variante de `_FakeEpgIngestPort` que registra el orden de
/// entrada/salida y queda bloqueada en la primera llamada hasta que el
/// test suelte `firstCallGate` — mismo patrón que
/// `_SequencedEpgRepository` de `run_purge_test.dart`, para probar que
/// dos `runOnce` concurrentes se serializan de verdad.
final class _SequencedEpgIngestPort implements EpgIngestPort {
  _SequencedEpgIngestPort({required this.order, required this.firstCallGate});

  final List<String> order;
  final Future<void> firstCallGate;
  int _calls = 0;

  @override
  Future<EpgImportStats?> ingestFor(Source source, {required DateTime now}) async {
    final callNumber = ++_calls;
    order.add('start-$callNumber');
    if (callNumber == 1) await firstCallGate;
    order.add('end-$callNumber');
    return null;
  }
}
