import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_pairing/iptv_pairing.dart';
import 'package:test/test.dart';

/// Desempate determinista y simétrico sobre contenido, para los tests:
/// nunca sobre metadatos de proceso (ver `Tiebreaker` en core).
bool _favoriteTiebreaker(Favorite a, Favorite b) {
  String key(Favorite f) => '${f.channel.serialized}|${f.order}|${f.deletedAt}';
  return key(a).compareTo(key(b)) >= 0;
}

LwwMerger<Favorite> _merger() => LwwMerger<Favorite>(
      keyOf: (f) => f.channel,
      tiebreaker: _favoriteTiebreaker,
    );

Favorite _fav(String key, {int order = 0, required DateTime at, DateTime? deletedAt}) =>
    Favorite(
      channel: ChannelRef(sourceId: 's1', key: key),
      order: order,
      updatedAt: at,
      deletedAt: deletedAt,
    );

/// Compara dos resultados de merge como *conjuntos*: el orden de la
/// lista de salida no forma parte del contrato (ver docstring de
/// `LwwMerger.merge`).
void _expectSameSet(List<Favorite> a, List<Favorite> b) {
  expect(a.toSet(), b.toSet());
}

void main() {
  group('LwwMerger.merge — casos de ejemplo', () {
    test('gana el updatedAt más reciente entre los dos lados', () {
      final local = [_fav('a', at: DateTime(2026, 1, 1))];
      final remote = [_fav('a', order: 1, at: DateTime(2026, 1, 2))];

      final result = _merger().merge(local, remote);

      expect(result, [remote.single]);
    });

    test('conserva las claves que solo están en un lado', () {
      final local = [_fav('a', at: DateTime(2026, 1, 1))];
      final remote = [_fav('b', at: DateTime(2026, 1, 1))];

      final result = _merger().merge(local, remote);

      expect(result.map((f) => f.channel.key).toSet(), {'a', 'b'});
    });

    test('un tombstone más reciente gana sobre un registro vivo', () {
      final local = [_fav('a', at: DateTime(2026, 1, 1))];
      final remote = [
        _fav('a', at: DateTime(2026, 1, 1, 1), deletedAt: DateTime(2026, 1, 1, 1)),
      ];

      final result = _merger().merge(local, remote);

      expect(result.single.isDeleted, isTrue);
    });
  });

  group('LwwMerger.merge — leyes del merge (base de la convergencia)', () {
    // Cada escenario ejercita las tres leyes con datos distintos: claves
    // disjuntas, claves compartidas con timestamps distintos, empates de
    // timestamp, y tombstones. Sin esto, dos dispositivos podrían acabar
    // en estados distintos según el orden en que se sincronizan.
    final scenarios = <String, (List<Favorite>, List<Favorite>, List<Favorite>)>{
      'claves disjuntas': (
        [_fav('a', at: DateTime(2026, 1, 1))],
        [_fav('b', at: DateTime(2026, 1, 1))],
        [_fav('c', at: DateTime(2026, 1, 1))],
      ),
      'misma clave, timestamps distintos': (
        [_fav('a', order: 1, at: DateTime(2026, 1, 1))],
        [_fav('a', order: 2, at: DateTime(2026, 1, 3))],
        [_fav('a', order: 3, at: DateTime(2026, 1, 2))],
      ),
      'empate exacto de timestamp': (
        [_fav('a', order: 1, at: DateTime(2026, 1, 1))],
        [_fav('a', order: 2, at: DateTime(2026, 1, 1))],
        [_fav('a', order: 3, at: DateTime(2026, 1, 1))],
      ),
      'tombstone frente a vivo': (
        [_fav('a', at: DateTime(2026, 1, 1))],
        [
          _fav('a', at: DateTime(2026, 1, 2), deletedAt: DateTime(2026, 1, 2)),
        ],
        [_fav('a', order: 5, at: DateTime(2026, 1, 1, 12))],
      ),
      'claves parcialmente solapadas': (
        [
          _fav('a', at: DateTime(2026, 1, 1)),
          _fav('b', at: DateTime(2026, 1, 1)),
        ],
        [
          _fav('b', order: 9, at: DateTime(2026, 1, 5)),
          _fav('c', at: DateTime(2026, 1, 1)),
        ],
        [_fav('a', order: 9, at: DateTime(2026, 1, 5))],
      ),
    };

    scenarios.forEach((name, lists) {
      final (a, b, c) = lists;

      test('$name — conmutativo: merge(a,b) == merge(b,a)', () {
        _expectSameSet(_merger().merge(a, b), _merger().merge(b, a));
      });

      test('$name — idempotente: merge(a,a) no duplica ni pierde nada', () {
        _expectSameSet(_merger().merge(a, a), a);
      });

      test('$name — asociativo: merge(merge(a,b),c) == merge(a,merge(b,c))', () {
        final left = _merger().merge(_merger().merge(a, b), c);
        final right = _merger().merge(a, _merger().merge(b, c));
        _expectSameSet(left, right);
      });
    });
  });

  group('LwwMerger.collectTombstones', () {
    test('conserva los registros vivos sin importar su antigüedad', () {
      final items = [_fav('a', at: DateTime(2020, 1, 1))];
      final result = _merger().collectTombstones(items, now: DateTime(2026, 1, 1));
      expect(result, items);
    });

    test('descarta tombstones más viejos que la ventana', () {
      final oldTombstone = _fav(
        'a',
        at: DateTime(2025, 1, 1),
        deletedAt: DateTime(2025, 1, 1),
      );
      final result = _merger().collectTombstones(
        [oldTombstone],
        now: DateTime(2026, 1, 1),
        window: const Duration(days: 30),
      );
      expect(result, isEmpty);
    });

    test('conserva tombstones dentro de la ventana', () {
      final recentTombstone = _fav(
        'a',
        at: DateTime(2025, 12, 20),
        deletedAt: DateTime(2025, 12, 20),
      );
      final result = _merger().collectTombstones(
        [recentTombstone],
        now: DateTime(2026, 1, 1),
        window: const Duration(days: 30),
      );
      expect(result, [recentTombstone]);
    });
  });
}
