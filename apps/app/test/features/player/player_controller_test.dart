import 'package:fake_async/fake_async.dart';
import 'package:iptv_app/features/player/playback_request.dart';
import 'package:iptv_app/features/player/playback_url_resolver.dart';
import 'package:iptv_app/features/player/player_controller.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:test/test.dart';

import '../home/_helpers/fake_watch_state_repository.dart';
import '../sources/_helpers/fakes.dart';
import '_helpers/fake_player_port.dart';

/// `PlayerController` (S6, Bloque C) — el temporizador de 10 s de
/// `watch_state`, el autoocultado del overlay a los 4 s y el zapping sobre
/// `PlaybackQueue`, todo sin `BuildContext`. Usa `fakeAsync` para controlar
/// el tiempo sin esperas reales (mismo criterio de determinismo que
/// `_FakeClock` en `packages/core/test`).
void main() {
  Channel liveChannel({String key = 'canal-1', String name = 'Canal 1'}) => Channel(
    ref: ChannelRef(sourceId: 's1', key: key),
    sourceId: 's1',
    type: ContentType.live,
    name: name,
    url: Uri.parse('http://cdn.example.com/live/$key.m3u8'),
  );

  Channel vodChannel({String key = 'peli-1'}) => Channel(
    ref: ChannelRef(sourceId: 's1', key: key),
    sourceId: 's1',
    type: ContentType.vod,
    name: 'Oppenheimer',
    url: Uri.parse('http://cdn.example.com/vod/$key.mp4'),
  );

  ({
    FakePlayerPort port,
    FakeWatchStateRepository watchState,
    PlayerController controller,
  })
  build({required PlaybackRequest request}) {
    final port = FakePlayerPort();
    final watchState = FakeWatchStateRepository();
    final trackWatchProgress = TrackWatchProgress(watchState, FixedClock(_fixedNow));
    final resolver = PlaybackUrlResolver(
      sources: FakeSourceRepository(),
      secureStore: FakeSecureCredentialStore(),
    );
    final controller = PlayerController(
      port: port,
      resolver: resolver,
      trackWatchProgress: trackWatchProgress,
      request: request,
    );
    return (port: port, watchState: watchState, controller: controller);
  }

  test('a los 10 s hay exactamente un upsert con la posición correcta', () {
    fakeAsync((async) {
      final setup = build(request: PlaybackRequest(channel: liveChannel()));
      setup.controller.initialize();
      async.flushMicrotasks();

      setup.port.emitPosition(const Duration(seconds: 7));
      async.elapse(const Duration(seconds: 10));

      expect(setup.watchState.upsertCalls, 1);
      expect(setup.watchState.upsertHistory.single.position, const Duration(seconds: 7));
      // directo: duration siempre Duration.zero, nunca lo que reporte el
      // motor (WatchState.duration, docstring de core).
      expect(setup.watchState.upsertHistory.single.duration, Duration.zero);

      setup.controller.dispose();
    });
  });

  test('a los 25 s hay dos upserts', () {
    fakeAsync((async) {
      final setup = build(request: PlaybackRequest(channel: vodChannel()));
      setup.port.durationOnOpen = const Duration(minutes: 120);
      setup.controller.initialize();
      async.flushMicrotasks();

      setup.port.emitPosition(const Duration(seconds: 10));
      async.elapse(const Duration(seconds: 10));
      setup.port.emitPosition(const Duration(seconds: 20));
      async.elapse(const Duration(seconds: 10));
      // A los 25s totales (dos ticks de 10s ya ocurrieron, el tercero cae
      // en 30s) solo dos upserts.
      async.elapse(const Duration(seconds: 5));

      expect(setup.watchState.upsertCalls, 2);
      expect(setup.watchState.upsertHistory.map((w) => w.position), [
        const Duration(seconds: 10),
        const Duration(seconds: 20),
      ]);

      setup.controller.dispose();
    });
  });

  test('dispose() hace un último upsert con la posición final', () {
    fakeAsync((async) {
      final setup = build(request: PlaybackRequest(channel: liveChannel()));
      setup.controller.initialize();
      async.flushMicrotasks();

      setup.port.emitPosition(const Duration(seconds: 3));
      setup.controller.dispose();
      async.flushMicrotasks();

      expect(setup.watchState.upsertCalls, 1);
      expect(setup.watchState.upsertHistory.single.position, const Duration(seconds: 3));
    });
  });

  test('el overlay se oculta a los 4 s', () {
    fakeAsync((async) {
      final setup = build(request: PlaybackRequest(channel: liveChannel()));
      setup.controller.initialize();
      async.flushMicrotasks();

      expect(setup.controller.overlayVisible, isTrue);
      async.elapse(const Duration(seconds: 4));

      expect(setup.controller.overlayVisible, isFalse);
      setup.controller.dispose();
    });
  });

  test('show() reinicia el contador de autoocultado', () {
    fakeAsync((async) {
      final setup = build(request: PlaybackRequest(channel: liveChannel()));
      setup.controller.initialize();
      async.flushMicrotasks();

      async.elapse(const Duration(seconds: 3));
      setup.controller.show(); // reinicia justo antes de que expire
      async.elapse(const Duration(seconds: 3));

      expect(setup.controller.overlayVisible, isTrue, reason: 'el segundo intervalo aún no llegó a 4s');

      async.elapse(const Duration(seconds: 1));
      expect(setup.controller.overlayVisible, isFalse);

      setup.controller.dispose();
    });
  });

  group('PlaybackQueue / zapping', () {
    test('next()/previous() recorren la cola y cargan el canal correcto', () {
      fakeAsync((async) {
        final channels = [liveChannel(key: 'a'), liveChannel(key: 'b'), liveChannel(key: 'c')];
        final setup = build(
          request: PlaybackRequest(
            channel: channels[1],
            queue: PlaybackQueue(items: channels, index: 1),
          ),
        );
        setup.controller.initialize();
        async.flushMicrotasks();

        expect(setup.controller.currentChannel.ref.key, 'b');

        setup.controller.next();
        async.flushMicrotasks();
        expect(setup.controller.currentChannel.ref.key, 'c');
        expect(setup.port.openedUrls.last, channels[2].url);

        setup.controller.previous();
        async.flushMicrotasks();
        setup.controller.previous();
        async.flushMicrotasks();
        expect(setup.controller.currentChannel.ref.key, 'a');

        setup.controller.dispose();
      });
    });

    test('next()/previous() se detienen en los extremos', () {
      fakeAsync((async) {
        final channels = [liveChannel(key: 'a'), liveChannel(key: 'b')];
        final setup = build(
          request: PlaybackRequest(channel: channels[0], queue: PlaybackQueue(items: channels, index: 0)),
        );
        setup.controller.initialize();
        async.flushMicrotasks();

        expect(setup.controller.canGoPrevious, isFalse);
        setup.controller.previous(); // no-op: ya está en el extremo
        async.flushMicrotasks();
        expect(setup.controller.currentChannel.ref.key, 'a');

        setup.controller.next();
        async.flushMicrotasks();
        expect(setup.controller.canGoNext, isFalse);
        setup.controller.next(); // no-op
        async.flushMicrotasks();
        expect(setup.controller.currentChannel.ref.key, 'b');

        setup.controller.dispose();
      });
    });

    test('sin cola, next()/previous() no hacen nada (D3)', () {
      fakeAsync((async) {
        final setup = build(request: PlaybackRequest(channel: liveChannel()));
        setup.controller.initialize();
        async.flushMicrotasks();

        expect(setup.controller.canGoNext, isFalse);
        expect(setup.controller.canGoPrevious, isFalse);

        setup.controller.dispose();
      });
    });
  });
}

final _fixedNow = DateTime.utc(2026, 8, 7, 21);
