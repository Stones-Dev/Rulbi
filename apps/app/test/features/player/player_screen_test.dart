import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/features/player/playback_request.dart';
import 'package:iptv_app/features/player/player_screen.dart';
import 'package:iptv_app/features/sources/source_providers.dart';
import 'package:iptv_app/l10n/app_localizations.dart';
import 'package:iptv_core/iptv_core.dart';

import '../../_helpers/fake_epg_repository.dart';
import '../home/_helpers/fake_watch_state_repository.dart';
import '../sources/_helpers/fakes.dart';
import '_helpers/fake_player_port.dart';

/// `PlayerScreen` (S6, Bloque C) — atajos de teclado y overlay contra un
/// `FakePlayerPort`, nunca `MediaKitPlayer` real (no testeable en CI, ver
/// docstring de `_defaultBuildSurface` en `player_screen.dart`). El
/// `buildSurface` inyectado sustituye la superficie de vídeo real por un
/// marcador de posición trivial.
void main() {
  Channel liveChannel() => Channel(
    ref: const ChannelRef(sourceId: 's1', key: 'canal-1'),
    sourceId: 's1',
    type: ContentType.live,
    name: 'Canal 1',
    url: Uri.parse('http://cdn.example.com/live/canal.m3u8'),
  );

  Future<FakePlayerPort> pumpScreen(WidgetTester tester, {PlaybackRequest? request}) async {
    final port = FakePlayerPort();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sourceRepositoryProvider.overrideWithValue(FakeSourceRepository()),
          secureCredentialStoreProvider.overrideWithValue(FakeSecureCredentialStore()),
          watchStateRepositoryProvider.overrideWithValue(FakeWatchStateRepository()),
          epgRepositoryProvider.overrideWithValue(FakeEpgRepository()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PlayerScreen(
            request: request ?? PlaybackRequest(channel: liveChannel()),
            createPort: () => port,
            buildSurface: (_, _) => const ColoredBox(color: Colors.black, key: Key('fakeSurface')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return port;
  }

  Future<void> focusAndPress(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.tap(find.byType(PlayerScreen));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  testWidgets('Espacio alterna play/pause sobre el FakePlayerPort', (tester) async {
    final port = await pumpScreen(tester);
    expect(port.currentState.status, PlaybackStatus.playing);

    await focusAndPress(tester, LogicalKeyboardKey.space);
    expect(port.currentState.status, PlaybackStatus.paused);

    await focusAndPress(tester, LogicalKeyboardKey.space);
    expect(port.currentState.status, PlaybackStatus.playing);
  });

  testWidgets('M silencia/reactiva', (tester) async {
    final port = await pumpScreen(tester);
    expect(port.currentState.muted, isFalse);

    await focusAndPress(tester, LogicalKeyboardKey.keyM);
    expect(port.currentState.muted, isTrue);

    await focusAndPress(tester, LogicalKeyboardKey.keyM);
    expect(port.currentState.muted, isFalse);
  });

  testWidgets('F alterna pantalla completa y oculta la barra de volver', (tester) async {
    await pumpScreen(tester);
    expect(find.byKey(const Key('playerOverlay.back')), findsOneWidget);

    await focusAndPress(tester, LogicalKeyboardKey.keyF);
    expect(find.byKey(const Key('playerOverlay.back')), findsNothing);

    await focusAndPress(tester, LogicalKeyboardKey.keyF);
    expect(find.byKey(const Key('playerOverlay.back')), findsOneWidget);
  });

  testWidgets('← / → hacen seek en VOD', (tester) async {
    final vod = Channel(
      ref: const ChannelRef(sourceId: 's1', key: 'peli-1'),
      sourceId: 's1',
      type: ContentType.vod,
      name: 'Oppenheimer',
      url: Uri.parse('http://cdn.example.com/vod/peli.mp4'),
    );
    final port = await pumpScreen(tester, request: PlaybackRequest(channel: vod));
    port.durationOnOpen = const Duration(minutes: 60);
    port.emitPosition(const Duration(minutes: 10));
    await tester.pumpAndSettle();

    await focusAndPress(tester, LogicalKeyboardKey.arrowRight);
    expect(port.currentState.position, const Duration(minutes: 10, seconds: 10));

    await focusAndPress(tester, LogicalKeyboardKey.arrowLeft);
    expect(port.currentState.position, const Duration(minutes: 10));
  });

  testWidgets('↑/↓ zapean sobre la PlaybackQueue y abren el siguiente canal', (tester) async {
    final channels = [
      liveChannel(),
      Channel(
        ref: const ChannelRef(sourceId: 's1', key: 'canal-2'),
        sourceId: 's1',
        type: ContentType.live,
        name: 'Canal 2',
        url: Uri.parse('http://cdn.example.com/live/canal2.m3u8'),
      ),
    ];
    final port = await pumpScreen(
      tester,
      request: PlaybackRequest(channel: channels[0], queue: PlaybackQueue(items: channels, index: 0)),
    );

    await focusAndPress(tester, LogicalKeyboardKey.arrowDown);
    expect(port.openedUrls.last, channels[1].url);

    await focusAndPress(tester, LogicalKeyboardKey.arrowUp);
    expect(port.openedUrls.last, channels[0].url);
  });

  testWidgets('el selector de pista de audio lista las pistas y las selecciona', (tester) async {
    final port = await pumpScreen(tester);
    port.seedTracks(
      const PlayerTracks(
        audio: [PlayerTrack(id: 'a1', language: 'es'), PlayerTrack(id: 'a2', language: 'en')],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('playerOverlay.audioTrack')).first);
    await tester.pumpAndSettle();
    // `warnIfMissed: false`: el hit test real cae en el `InkWell` del
    // `PopupMenuItem`, no en el `RenderParagraph` exacto del texto — el
    // tap sí llega al ítem correcto (lo confirma la aserción siguiente).
    await tester.tap(find.text('en').last, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(port.currentTracks.selectedAudioId, 'a2');
  });
}
