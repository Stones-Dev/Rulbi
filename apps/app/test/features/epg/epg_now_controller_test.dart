import 'package:iptv_app/features/epg/epg_providers.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:test/test.dart';

import '../../_helpers/fake_epg_repository.dart';

/// `EpgNowController` — fallback bajo demanda de EPG Xtream (S5.5, Bloque
/// A3): [EpgNowController.request] opcionalmente trae el [Channel], y
/// [EpgNowController.ensureEpgFor] se invoca como mucho una vez por
/// `tvgId` sin "ahora/siguiente" mientras el controller viva. Sin
/// `channel`/`ensureEpgFor`, el comportamiento es exactamente el de antes
/// de esta ola (ver primer grupo).
void main() {
  final now = DateTime.utc(2026, 8, 7, 12);

  Channel channelOf(String tvgId) => Channel(
    ref: ChannelRef(sourceId: 's1', key: tvgId),
    sourceId: 's1',
    type: ContentType.live,
    name: 'Canal $tvgId',
    url: Uri.parse('xtream://s1/live/1'),
    tvgId: tvgId,
    metadata: const {'x-xtream-stream-id': '1'},
  );

  group('sin ensureEpgFor (comportamiento previo a S5.5)', () {
    test('un tvgId sin programas se marca resuelto y no repite consultas', () async {
      final repository = FakeEpgRepository();
      final controller = EpgNowController(repository: repository);

      controller.request('canal.1', now);
      await Future<void>.delayed(Duration.zero);
      controller.request('canal.1', now); // segunda vez: ya está en _known.
      await Future<void>.delayed(Duration.zero);

      expect(controller.nowAiring('canal.1'), isNull);
    });
  });

  group('con ensureEpgFor, sin channel en request', () {
    test('nunca se invoca — no hay Channel que pasarle', () async {
      final repository = FakeEpgRepository();
      var calls = 0;
      final controller = EpgNowController(
        repository: repository,
        ensureEpgFor: (channel, at) async {
          calls++;
          return false;
        },
      );

      controller.request('canal.1', now); // sin channel:
      await Future<void>.delayed(Duration.zero);

      expect(calls, 0);
    });
  });

  group('con ensureEpgFor y channel', () {
    test('se invoca una vez para un tvgId sin ahora/siguiente', () async {
      final repository = FakeEpgRepository();
      final calls = <String?>[];
      final controller = EpgNowController(
        repository: repository,
        ensureEpgFor: (channel, at) async {
          calls.add(channel.tvgId);
          return false;
        },
      );

      controller.request('canal.1', now, channel: channelOf('canal.1'));
      await Future<void>.delayed(Duration.zero);
      // Microtask extra: _tryFallback se agenda con unawaited dentro de
      // _flush, necesita un segundo tick para completar su propio await.
      await Future<void>.delayed(Duration.zero);

      expect(calls, ['canal.1']);
    });

    test('no se invoca si el tvgId ya tenía ahora/siguiente en drift', () async {
      final repository = FakeEpgRepository()
        ..seed(
          EpgProgramme(
            tvgId: 'canal.1',
            start: now.subtract(const Duration(minutes: 10)),
            stop: now.add(const Duration(minutes: 20)),
            title: 'Ya en drift',
          ),
        );
      var calls = 0;
      final controller = EpgNowController(
        repository: repository,
        ensureEpgFor: (channel, at) async {
          calls++;
          return false;
        },
      );

      controller.request('canal.1', now, channel: channelOf('canal.1'));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(calls, 0);
      expect(controller.nowAiring('canal.1')?.title, 'Ya en drift');
    });

    test('si el fallback escribe datos nuevos (true), el controller los recoge sin que la fila reintente a mano', () async {
      final repository = FakeEpgRepository();
      final controller = EpgNowController(
        repository: repository,
        ensureEpgFor: (channel, at) async {
          // Simula lo que XtreamEpgFallback.ensureEpgFor hace de verdad:
          // escribe en el repositorio subyacente y devuelve true.
          repository.seed(
            EpgProgramme(
              tvgId: channel.tvgId!,
              start: at.subtract(const Duration(minutes: 5)),
              stop: at.add(const Duration(minutes: 25)),
              title: 'Recién traído por el fallback',
            ),
          );
          return true;
        },
      );

      controller.request('canal.1', now, channel: channelOf('canal.1'));
      // Tres ticks: _flush inicial (no encuentra nada) -> _tryFallback
      // (escribe y devuelve true) -> request() de reintento -> _flush de
      // reintento (ahora sí encuentra el programa).
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(controller.nowAiring('canal.1')?.title, 'Recién traído por el fallback');
    });

    test('un fallback que lanza no rompe el controller (P7, best-effort)', () async {
      final repository = FakeEpgRepository();
      final controller = EpgNowController(
        repository: repository,
        ensureEpgFor: (channel, at) async {
          throw StateError('fallo simulado de red');
        },
      );

      controller.request('canal.1', now, channel: channelOf('canal.1'));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(controller.nowAiring('canal.1'), isNull);
    });
  });
}
