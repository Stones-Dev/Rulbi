import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/features/sources/import_controller.dart';
import 'package:iptv_app/features/sources/import_status_bar.dart';
import 'package:iptv_app/features/sources/source_providers.dart';
import 'package:iptv_app/l10n/app_localizations.dart';
import 'package:iptv_core/iptv_core.dart';

import '_helpers/fakes.dart';

/// Chip global de import en segundo plano (ui-spec §2.14, S4 · Ola 3):
/// solo visible mientras hay un [ImportRunning] activo, en cualquier
/// sección de `DesktopShell`.
void main() {
  Channel channel(String refKey) => Channel(
    ref: ChannelRef(sourceId: 's1', key: refKey),
    sourceId: 's1',
    type: ContentType.live,
    name: 'Canal $refKey',
    url: Uri.parse('http://example.com/$refKey'),
  );

  Widget wrap(ProviderContainer container, Widget child) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    );
  }

  testWidgets('no muestra nada cuando no hay import en curso (ImportIdle)', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(wrap(container, const ImportStatusBar()));

    expect(find.byType(ImportStatusBar), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('aparece con el nombre de la fuente mientras el import corre', (
    tester,
  ) async {
    final sources = FakeSourceRepository();
    final channels = FakeChannelRepository();
    final rawController = StreamController<Channel>();
    addTearDown(() {
      if (!rawController.isClosed) rawController.close();
    });
    final importSource = FakeImportChannelSource(channels: rawController.stream);
    final source = Source(
      id: 's1',
      config: M3uUrlSourceConfig(url: Uri.parse('http://host/list.m3u')),
      name: 'Mi lista',
      updatedAt: DateTime.utc(2026, 8, 1),
    );
    final container = ProviderContainer(
      overrides: [
        sourceRepositoryProvider.overrideWithValue(sources),
        channelRepositoryProvider.overrideWithValue(channels),
        secureCredentialStoreProvider.overrideWithValue(FakeSecureCredentialStore()),
        clockProvider.overrideWithValue(FixedClock(DateTime.utc(2026, 8, 6))),
        m3uImportChannelSourceProvider.overrideWithValue(importSource),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(wrap(container, const ImportStatusBar()));
    expect(find.text('Importing Mi lista…'), findsNothing);

    unawaited(container.read(importControllerProvider.notifier).start(source));
    await tester.pump();

    expect(find.text('Importing Mi lista…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('desaparece cuando el import termina (ImportDone)', (
    tester,
  ) async {
    final sources = FakeSourceRepository();
    final channels = FakeChannelRepository();
    final importSource = FakeImportChannelSource(
      channels: Stream.fromIterable([channel('a')]),
    );
    final source = Source(
      id: 's1',
      config: M3uUrlSourceConfig(url: Uri.parse('http://host/list.m3u')),
      name: 'Mi lista',
      updatedAt: DateTime.utc(2026, 8, 1),
    );
    final container = ProviderContainer(
      overrides: [
        sourceRepositoryProvider.overrideWithValue(sources),
        channelRepositoryProvider.overrideWithValue(channels),
        secureCredentialStoreProvider.overrideWithValue(FakeSecureCredentialStore()),
        clockProvider.overrideWithValue(FixedClock(DateTime.utc(2026, 8, 6))),
        m3uImportChannelSourceProvider.overrideWithValue(importSource),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(wrap(container, const ImportStatusBar()));
    // `await`-ar `start()` directamente en un `testWidgets` (en vez de
    // `unawaited` + `pump()`) puede colgar el binding de test de Flutter
    // esperando un frame que nunca llega a programarse a través del ciclo
    // de pump — patrón ya usado en el resto de tests de este archivo.
    unawaited(container.read(importControllerProvider.notifier).start(source));
    await tester.pump();

    expect(container.read(importControllerProvider), isA<ImportDone>());
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('al pulsarlo navega a ImportScreen', (tester) async {
    final sources = FakeSourceRepository();
    final channels = FakeChannelRepository();
    final rawController = StreamController<Channel>();
    addTearDown(() {
      if (!rawController.isClosed) rawController.close();
    });
    final importSource = FakeImportChannelSource(channels: rawController.stream);
    final source = Source(
      id: 's1',
      config: M3uUrlSourceConfig(url: Uri.parse('http://host/list.m3u')),
      name: 'Mi lista',
      updatedAt: DateTime.utc(2026, 8, 1),
    );
    final container = ProviderContainer(
      overrides: [
        sourceRepositoryProvider.overrideWithValue(sources),
        channelRepositoryProvider.overrideWithValue(channels),
        secureCredentialStoreProvider.overrideWithValue(FakeSecureCredentialStore()),
        clockProvider.overrideWithValue(FixedClock(DateTime.utc(2026, 8, 6))),
        m3uImportChannelSourceProvider.overrideWithValue(importSource),
      ],
    );
    addTearDown(container.dispose);

    unawaited(container.read(importControllerProvider.notifier).start(source));
    await tester.pumpWidget(
      wrap(
        container,
        Scaffold(appBar: AppBar(), body: const ImportStatusBar()),
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(ImportStatusBar));
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }

    expect(find.text('Importing Mi lista'), findsOneWidget); // título de ImportScreen
  });
}
