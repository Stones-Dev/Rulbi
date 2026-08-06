import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/features/home/home_screen.dart';
import 'package:iptv_app/features/sources/source_providers.dart';
import 'package:iptv_app/l10n/app_localizations.dart';
import 'package:iptv_core/iptv_core.dart';

import '../channels/_helpers/fake_channel_repository.dart';
import '../sources/_helpers/fakes.dart';
import '_helpers/fake_watch_state_repository.dart';

/// Home desktop (ui-spec §2.2, S5 · Ola 1) — solo la fila "Continuar
/// viendo" está implementada esta ola; Favoritos/Ahora quedan en Ola 2
/// (huecos estructurales, sin datos falsos).
void main() {
  Source activeSource({String id = 's1'}) => Source(
    id: id,
    config: M3uUrlSourceConfig(url: Uri.parse('http://example.com/$id.m3u')),
    name: 'Fuente $id',
    updatedAt: DateTime.utc(2026, 1, 1),
  );

  Channel channelOf(
    String sourceId,
    String key,
    String name, {
    ContentType type = ContentType.vod,
  }) => Channel(
    ref: ChannelRef(sourceId: sourceId, key: key),
    sourceId: sourceId,
    type: type,
    name: name,
    url: Uri.parse('http://example.com/$sourceId/$key'),
  );

  Future<void> pumpScreen(
    WidgetTester tester, {
    required FakeSourceRepository sources,
    required FakeChannelListRepository channels,
    required FakeWatchStateRepository watchState,
    VoidCallback? onGoToSources,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sourceRepositoryProvider.overrideWithValue(sources),
          channelRepositoryProvider.overrideWithValue(channels),
          watchStateRepositoryProvider.overrideWithValue(watchState),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: HomeScreen(onGoToSources: onGoToSources ?? () {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('sin fuentes, muestra el estado vacío con CTA a Fuentes', (
    tester,
  ) async {
    var tapped = false;
    await pumpScreen(
      tester,
      sources: FakeSourceRepository(),
      channels: FakeChannelListRepository(),
      watchState: FakeWatchStateRepository(),
      onGoToSources: () => tapped = true,
    );

    expect(find.text('Your library is empty'), findsOneWidget);

    await tester.tap(find.byKey(const Key('homeGoToSourcesButton')));
    expect(tapped, isTrue);
  });

  testWidgets(
    'con fuentes pero sin historial, no muestra la fila (sin datos falsos)',
    (tester) async {
      final sources = FakeSourceRepository();
      await sources.upsert(activeSource());

      await pumpScreen(
        tester,
        sources: sources,
        channels: FakeChannelListRepository(),
        watchState: FakeWatchStateRepository(),
      );

      expect(find.text('Your library is empty'), findsNothing);
      expect(find.text('Continue watching'), findsNothing);
    },
  );

  testWidgets(
    'con historial real, muestra la fila con nombre, progreso y tiempo restante',
    (tester) async {
      final sources = FakeSourceRepository();
      await sources.upsert(activeSource());

      final channel = channelOf('s1', 'oppenheimer', 'Oppenheimer');
      final channels = FakeChannelListRepository(channels: [channel]);

      final watchState = FakeWatchStateRepository()
        ..seed(
          WatchState(
            channel: channel.ref,
            position: const Duration(minutes: 30),
            duration: const Duration(hours: 2),
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        );

      await pumpScreen(
        tester,
        sources: sources,
        channels: channels,
        watchState: watchState,
      );

      expect(find.text('Continue watching'), findsOneWidget);
      expect(find.text('Oppenheimer'), findsOneWidget);
      // 90 min quedan de 120 -> 1h 30m.
      expect(find.text('1h 30m left'), findsOneWidget);
    },
  );

  testWidgets('un ítem en directo (duration cero) no muestra tiempo restante', (
    tester,
  ) async {
    final sources = FakeSourceRepository();
    await sources.upsert(activeSource());

    final channel = channelOf('s1', 'dazn1', 'DAZN 1', type: ContentType.live);
    final channels = FakeChannelListRepository(channels: [channel]);

    final watchState = FakeWatchStateRepository()
      ..seed(
        WatchState(
          channel: channel.ref,
          position: const Duration(minutes: 10),
          duration: Duration.zero,
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );

    await pumpScreen(
      tester,
      sources: sources,
      channels: channels,
      watchState: watchState,
    );

    expect(find.text('DAZN 1'), findsOneWidget);
    expect(find.textContaining('left'), findsNothing);
  });
}
