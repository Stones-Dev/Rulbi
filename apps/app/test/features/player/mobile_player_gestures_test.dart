import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/features/player/mobile_player_gestures.dart';
import 'package:iptv_app/features/player/playback_request.dart';
import 'package:iptv_app/features/player/playback_url_resolver.dart';
import 'package:iptv_app/features/player/player_controller.dart';
import 'package:iptv_app/l10n/app_localizations.dart';
import 'package:iptv_core/iptv_core.dart';

import '../home/_helpers/fake_watch_state_repository.dart';
import '../sources/_helpers/fakes.dart';
import '_helpers/fake_player_port.dart';

void main() {
  Channel vodChannel() => Channel(
        ref: const ChannelRef(sourceId: 's1', key: 'vod-1'),
        sourceId: 's1',
        type: ContentType.vod,
        name: 'Película VOD',
        url: Uri.parse('http://cdn.example.com/vod/movie.mp4'),
      );

  PlayerController createController({required FakePlayerPort port}) {
    final watchState = FakeWatchStateRepository();
    final trackWatchProgress = TrackWatchProgress(
      watchState,
      FixedClock(DateTime.utc(2026, 8, 7, 21)),
    );
    final resolver = PlaybackUrlResolver(
      sources: FakeSourceRepository(),
      secureStore: FakeSecureCredentialStore(),
    );
    final controller = PlayerController(
      port: port,
      resolver: resolver,
      trackWatchProgress: trackWatchProgress,
      request: PlaybackRequest(channel: vodChannel()),
    );
    controller.initialize();
    return controller;
  }

  testWidgets('Doble tap a la derecha avanza +10s y muestra feedback visual', (tester) async {
    final port = FakePlayerPort()..durationOnOpen = const Duration(minutes: 10);
    final controller = createController(port: port);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 450,
            child: MobilePlayerGestures(
              controller: controller,
              child: const ColoredBox(color: Colors.black),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    port.emitPosition(const Duration(seconds: 30));
    await tester.pump();

    // Doble tap en la mitad derecha (x: 600, y: 225)
    await tester.tapAt(const Offset(600, 225));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(const Offset(600, 225));
    await tester.pump();

    // Comprueba que aparece la etiqueta de feedback +10s
    expect(find.text('+10s'), findsOneWidget);
    expect(port.currentState.position, const Duration(seconds: 40));

    // Deshacer temporizadores
    await tester.pump(const Duration(seconds: 2));
    controller.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('Doble tap a la izquierda retrocede -10s y muestra feedback visual', (tester) async {
    final port = FakePlayerPort()..durationOnOpen = const Duration(minutes: 10);
    final controller = createController(port: port);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 450,
            child: MobilePlayerGestures(
              controller: controller,
              child: const ColoredBox(color: Colors.black),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    port.emitPosition(const Duration(seconds: 30));
    await tester.pump();

    // Doble tap en la mitad izquierda (x: 200, y: 225)
    await tester.tapAt(const Offset(200, 225));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(const Offset(200, 225));
    await tester.pump();

    // Comprueba que aparece la etiqueta de feedback -10s
    expect(find.text('-10s'), findsOneWidget);
    expect(port.currentState.position, const Duration(seconds: 20));

    // Deshacer temporizadores
    await tester.pump(const Duration(seconds: 2));
    controller.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
