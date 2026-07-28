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

final class _FakeChannelSearchPort implements ChannelSearchPort {
  List<Channel> results = const [];
  String? lastQuery;

  @override
  Future<List<Channel>> search(String query, {int limit = 50}) async {
    lastQuery = query;
    return results.take(limit).toList();
  }
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
  });
}
