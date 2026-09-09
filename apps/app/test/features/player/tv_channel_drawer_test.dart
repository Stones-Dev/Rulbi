import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/features/player/playback_request.dart';
import 'package:iptv_app/features/player/playback_url_resolver.dart';
import 'package:iptv_app/features/player/player_controller.dart';
import 'package:iptv_app/features/player/tv_channel_drawer.dart';
import 'package:iptv_app/l10n/app_localizations.dart';
import 'package:iptv_core/iptv_core.dart';

import '../home/_helpers/fake_watch_state_repository.dart';
import '../sources/_helpers/fakes.dart';
import '_helpers/fake_player_port.dart';

void main() {
  Channel liveChannel({required String key, required String name, String? category}) => Channel(
        ref: ChannelRef(sourceId: 's1', key: key),
        sourceId: 's1',
        type: ContentType.live,
        name: name,
        url: Uri.parse('http://cdn.example.com/live/$key.m3u8'),
        categoryId: category,
      );

  PlayerController createController({
    required List<Channel> channels,
    int initialIndex = 0,
  }) {
    final port = FakePlayerPort();
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
      request: PlaybackRequest(
        channel: channels[initialIndex],
        queue: PlaybackQueue(items: channels, index: initialIndex),
      ),
    );
    controller.initialize();
    return controller;
  }

  testWidgets('TvChannelDrawer renderiza la lista de canales con el activo seleccionado',
      (tester) async {
    final channels = [
      liveChannel(key: 'la1', name: 'La 1 HD', category: 'Generalistas'),
      liveChannel(key: 'la2', name: 'La 2 HD', category: 'Generalistas'),
      liveChannel(key: 'antena3', name: 'Antena 3', category: 'Nacionales'),
    ];

    final controller = createController(channels: channels, initialIndex: 1);

    var closed = false;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: TvChannelDrawer(
            controller: controller,
            onClose: () => closed = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verifica que se muestran los canales
    expect(find.text('La 1 HD'), findsOneWidget);
    expect(find.text('La 2 HD'), findsOneWidget);
    expect(find.text('Antena 3'), findsOneWidget);

    // Verifica la insignia EN VIVO en el seleccionado (índice 1 -> La 2 HD)
    expect(find.text('EN VIVO'), findsOneWidget);

    // Tocar el canal 0 (La 1 HD) debe disparar jumpTo
    await tester.tap(find.text('La 1 HD'));
    await tester.pumpAndSettle();

    expect(controller.currentChannel.ref.key, 'la1');

    // Pulsar tecla Escape / Back debe disparar onClose
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(closed, isTrue);

    controller.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
