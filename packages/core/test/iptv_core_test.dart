import 'package:iptv_core/iptv_core.dart';
import 'package:test/test.dart';

void main() {
  test('el paquete core carga sin depender de Flutter', () {
    expect(true, isTrue);
  });

  group('ChannelRef.derive', () {
    test('prefiere tvg-id sobre url y nombre', () {
      final ref = ChannelRef.derive(
        sourceId: 's1',
        tvgId: 'canal.24h',
        url: 'http://example.com/stream1',
        name: 'Canal 24H',
      );
      expect(ref, ChannelRef(sourceId: 's1', key: 'canal.24h'));
    });

    test('cae a la url si no hay tvg-id', () {
      final ref = ChannelRef.derive(
        sourceId: 's1',
        url: 'http://example.com/stream1',
        name: 'Canal 24H',
      );
      expect(ref.key, 'http://example.com/stream1');
    });

    test('cae al nombre normalizado si no hay tvg-id ni url', () {
      final ref = ChannelRef.derive(sourceId: 's1', name: 'España TV');
      expect(ref.key, 'espana tv');
    });

    test(
      'es determinista: mismo canal en dos dispositivos produce el mismo ref',
      () {
        final a = ChannelRef.derive(sourceId: 's1', tvgId: 'ES1', name: 'x');
        final b = ChannelRef.derive(sourceId: 's1', tvgId: 'ES1', name: 'y');
        expect(a, b);
        expect(a.hashCode, b.hashCode);
      },
    );

    test('ignora tvg-id/url en blanco y cae al siguiente candidato', () {
      final ref = ChannelRef.derive(
        sourceId: 's1',
        tvgId: '   ',
        url: '  ',
        name: 'Canal X',
      );
      expect(ref.key, 'canal x');
    });

    test('serialized combina sourceId y key de forma estable', () {
      final ref = ChannelRef(sourceId: 's1', key: 'k');
      expect(ref.serialized, 's1::k');
    });
  });

  group('Category.derive', () {
    test('deriva el id de sourceId + nombre normalizado', () {
      final category = Category.derive(
        sourceId: 's1',
        type: ContentType.live,
        name: 'España',
      );
      expect(category.id, 's1::espana');
    });

    test(
      'es determinista: mismo group-title en dos dispositivos produce el mismo id',
      () {
        final a = Category.derive(
          sourceId: 's1',
          type: ContentType.live,
          name: 'Noticias',
        );
        final b = Category.derive(
          sourceId: 's1',
          type: ContentType.live,
          name: 'NOTICIAS',
        );
        expect(a.id, b.id);
      },
    );
  });

  group('normalizeForMatching', () {
    test('quita acentos y normaliza mayúsculas', () {
      expect(normalizeForMatching('España'), 'espana');
      expect(normalizeForMatching('ESPAÑA'), 'espana');
      expect(normalizeForMatching('Éxito Ñandú'), 'exito nandu');
    });

    test('recorta espacios', () {
      expect(normalizeForMatching('  Canal  '), 'canal');
    });
  });

  group('resolveConflict (LWW)', () {
    bool tiebreaker(Favorite a, Favorite b) => a.order >= b.order;

    test('gana el updatedAt estrictamente mayor', () {
      final older = Favorite(
        channel: const ChannelRef(sourceId: 's', key: 'k'),
        updatedAt: DateTime(2026, 1, 1),
      );
      final newer = Favorite(
        channel: const ChannelRef(sourceId: 's', key: 'k'),
        updatedAt: DateTime(2026, 1, 2),
      );
      expect(
        resolveConflict(older, newer, tiebreaker: tiebreaker),
        same(newer),
      );
      expect(
        resolveConflict(newer, older, tiebreaker: tiebreaker),
        same(newer),
      );
    });

    test('un tombstone más reciente gana sobre un registro vivo', () {
      final alive = Favorite(
        channel: const ChannelRef(sourceId: 's', key: 'k'),
        updatedAt: DateTime(2026, 1, 1),
      );
      final tombstone = alive.markDeleted(DateTime(2026, 1, 2));
      final winner = resolveConflict(alive, tombstone, tiebreaker: tiebreaker);
      expect(winner.isDeleted, isTrue);
    });

    test('en empate exacto, decide el tiebreaker', () {
      final at = DateTime(2026, 1, 1);
      final a = Favorite(
        channel: const ChannelRef(sourceId: 's', key: 'k'),
        updatedAt: at,
        order: 1,
      );
      final b = Favorite(
        channel: const ChannelRef(sourceId: 's', key: 'k'),
        updatedAt: at,
        order: 2,
      );
      expect(resolveConflict(a, b, tiebreaker: tiebreaker), same(b));
    });
  });

  group('Syncable', () {
    test('isDeleted refleja deletedAt', () {
      final favorite = Favorite(
        channel: const ChannelRef(sourceId: 's', key: 'k'),
        updatedAt: DateTime(2026, 1, 1),
      );
      expect(favorite.isDeleted, isFalse);
      expect(favorite.markDeleted(DateTime(2026, 1, 2)).isDeleted, isTrue);
    });
  });

  group('WatchState', () {
    test('fraction es 0 para directo (duration cero)', () {
      final state = WatchState(
        channel: const ChannelRef(sourceId: 's', key: 'k'),
        position: const Duration(minutes: 5),
        duration: Duration.zero,
        updatedAt: DateTime(2026, 1, 1),
      );
      expect(state.fraction, 0);
    });

    test('isFinished a partir del 95%', () {
      final state = WatchState(
        channel: const ChannelRef(sourceId: 's', key: 'k'),
        position: const Duration(minutes: 96),
        duration: const Duration(minutes: 100),
        updatedAt: DateTime(2026, 1, 1),
      );
      expect(state.isFinished, isTrue);
    });
  });

  group('Source', () {
    test('kind se deriva del tipo de config, exhaustivo por switch', () {
      final xtream = Source(
        id: 'x1',
        config: XtreamSourceConfig(
          host: Uri.parse('http://panel.example.com'),
          username: 'user',
        ),
        name: 'Mi panel',
        updatedAt: DateTime(2026, 1, 1),
      );
      expect(xtream.kind, SourceKind.xtream);
    });

    test('markDeleted preserva el resto de campos', () {
      final source = Source(
        id: 'x1',
        config: const M3uFileSourceConfig(filePath: '/tmp/list.m3u'),
        name: 'Mi lista',
        updatedAt: DateTime(2026, 1, 1),
      );
      final deleted = source.markDeleted(DateTime(2026, 1, 2));
      expect(deleted.deletedAt, DateTime(2026, 1, 2));
      expect(deleted.name, source.name);
      expect(deleted.config, source.config);
    });
  });
}
