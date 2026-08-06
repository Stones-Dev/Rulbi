import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/features/sources/import_controller.dart';
import 'package:iptv_app/features/sources/import_screen.dart';
import 'package:iptv_app/features/sources/source_providers.dart';
import 'package:iptv_app/l10n/app_localizations.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_protocols/iptv_protocols.dart';

import '_helpers/fakes.dart';
import '_helpers/form_harness.dart';

/// Pantalla de importación (ui-spec §2.14, S4 · Ola 3): progreso, informe
/// final con incidencias, fallo y cancelación. Sin red/isolate real —
/// mismas fakes que `import_controller_test.dart`.
void main() {
  Channel channel(String refKey) => Channel(
    ref: ChannelRef(sourceId: 's1', key: refKey),
    sourceId: 's1',
    type: ContentType.live,
    name: 'Canal $refKey',
    url: Uri.parse('http://example.com/$refKey'),
  );

  Source newM3uSource({DateTime? lastRefresh}) => Source(
    id: 's1',
    config: M3uUrlSourceConfig(url: Uri.parse('http://host/list.m3u')),
    name: 'Mi lista',
    updatedAt: DateTime.utc(2026, 8, 1),
    lastRefresh: lastRefresh,
  );

  /// `pumpAndSettle()` nunca termina mientras la pantalla muestra
  /// `LinearProgressIndicator()` indeterminado (animación infinita) — los
  /// tests que dejan el import deliberadamente "colgado" en
  /// [ImportRunning] (stream sin cerrar, para poder cancelar a mitad)
  /// usan este pump acotado en su lugar.
  Future<void> pumpFewFrames(WidgetTester tester, [int times = 5]) async {
    for (var i = 0; i < times; i++) {
      await tester.pump();
    }
  }

  List<Override> baseOverrides({
    required FakeSourceRepository sources,
    required FakeChannelRepository channels,
    required ImportChannelSource m3uSource,
    int progressEvery = 250,
  }) => [
    sourceRepositoryProvider.overrideWithValue(sources),
    channelRepositoryProvider.overrideWithValue(channels),
    secureCredentialStoreProvider.overrideWithValue(FakeSecureCredentialStore()),
    clockProvider.overrideWithValue(FixedClock(DateTime.utc(2026, 8, 6))),
    m3uImportChannelSourceProvider.overrideWithValue(m3uSource),
    importControllerProvider.overrideWith(
      () => ImportController(
        progressEvery: progressEvery,
        progressInterval: const Duration(days: 1),
      ),
    ),
  ];

  testWidgets(
    'arranca el import al abrir y muestra el informe final con SourceImportStats',
    (tester) async {
      final sources = FakeSourceRepository();
      final channels = FakeChannelRepository();
      final importSource = FakeImportChannelSource(
        channels: Stream.fromIterable([channel('a'), channel('b')]),
      );
      final source = newM3uSource();

      await pumpSourceForm(
        tester,
        ImportScreen(source: source),
        overrides: baseOverrides(
          sources: sources,
          channels: channels,
          m3uSource: importSource,
        ),
      );

      expect(find.text('Importing Mi lista'), findsOneWidget);
      expect(find.text('Import complete'), findsOneWidget);
      expect(find.text('2 new channels'), findsOneWidget);
      expect(find.text('No channels updated'), findsOneWidget);
      expect(channels.importedChannels, hasLength(2));
    },
  );

  testWidgets(
    'informe con incidencias: el toggle "Ver incidencias" expande la lista',
    (tester) async {
      final sources = FakeSourceRepository();
      final channels = FakeChannelRepository();
      const report = ImportReport(
        parsed: 1,
        discarded: [
          DiscardedLine(lineNumber: 4, rawLine: '#EXTINF sin URL', reason: 'sin URL'),
        ],
      );
      final importSource = FakeImportChannelSource(
        channels: Stream.fromIterable([channel('a')]),
        summary: const M3uImportSummary(report),
      );

      await pumpSourceForm(
        tester,
        ImportScreen(source: newM3uSource()),
        overrides: baseOverrides(
          sources: sources,
          channels: channels,
          m3uSource: importSource,
        ),
      );

      expect(find.text('View 1 issue'), findsOneWidget);
      expect(find.text('Line 4: sin URL'), findsNothing);

      await tester.tap(find.byKey(const Key('importScreen.issuesToggle')));
      await tester.pumpAndSettle();

      expect(find.text('Line 4: sin URL'), findsOneWidget);
    },
  );

  testWidgets('fallo a mitad de stream: motivo i18n + acción sugerida', (
    tester,
  ) async {
    final sources = FakeSourceRepository();
    final channels = FakeChannelRepository();
    final importSource = FakeImportChannelSource(
      channels: Stream<Channel>.multi((controller) {
        controller.addError(const SocketException('caída de red'));
        controller.close();
      }),
    );

    await pumpSourceForm(
      tester,
      ImportScreen(source: newM3uSource()),
      overrides: baseOverrides(
        sources: sources,
        channels: channels,
        m3uSource: importSource,
      ),
    );

    expect(find.text('Import failed'), findsOneWidget);
    expect(find.text('Network error. Check your connection.'), findsOneWidget);
    expect(
      find.text('You can try again from the Sources screen.'),
      findsOneWidget,
    );
  });

  testWidgets('cancelar: pantalla de cancelación, sin cambios confirmados', (
    tester,
  ) async {
    final sources = FakeSourceRepository();
    final existing = newM3uSource(lastRefresh: DateTime.utc(2026, 8, 2));
    await sources.upsert(existing);
    final channels = FakeChannelRepository();
    final rawController = StreamController<Channel>();
    addTearDown(() {
      if (!rawController.isClosed) rawController.close();
    });
    final importSource = FakeImportChannelSource(channels: rawController.stream);

    await tester.pumpWidget(
      ProviderScope(
        overrides: baseOverrides(
          sources: sources,
          channels: channels,
          m3uSource: importSource,
        ),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ImportScreen(source: existing),
        ),
      ),
    );
    await pumpFewFrames(tester);

    expect(find.text('Cancel import'), findsOneWidget);
    await tester.tap(find.text('Cancel import'));
    await pumpFewFrames(tester);

    expect(find.text('Import cancelled'), findsOneWidget);
    expect(
      find.text('No changes were made — the source is unchanged.'),
      findsOneWidget,
    );
    expect(channels.importedChannels, isEmpty);
  });

  testWidgets('Segundo plano: hace pop y el import sigue en curso', (
    tester,
  ) async {
    final sources = FakeSourceRepository();
    final channels = FakeChannelRepository();
    final rawController = StreamController<Channel>();
    addTearDown(() {
      if (!rawController.isClosed) rawController.close();
    });
    final importSource = FakeImportChannelSource(channels: rawController.stream);
    final container = ProviderContainer(
      overrides: baseOverrides(
        sources: sources,
        channels: channels,
        m3uSource: importSource,
      ),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  key: openButtonKey,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ImportScreen(source: newM3uSource()),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(openButtonKey));
    await pumpFewFrames(tester);

    expect(find.text('Continue in background'), findsOneWidget);
    await tester.tap(find.text('Continue in background'));
    await pumpFewFrames(tester);

    expect(find.byKey(openButtonKey), findsOneWidget);
    expect(container.read(importControllerProvider), isA<ImportRunning>());
  });

  testWidgets('claves i18n en español (Importación completa)', (tester) async {
    final sources = FakeSourceRepository();
    final channels = FakeChannelRepository();
    final importSource = FakeImportChannelSource(
      channels: Stream.fromIterable([channel('a')]),
    );

    await pumpSourceForm(
      tester,
      ImportScreen(source: newM3uSource()),
      locale: const Locale('es'),
      overrides: baseOverrides(
        sources: sources,
        channels: channels,
        m3uSource: importSource,
      ),
    );

    expect(find.text('Importando Mi lista'), findsOneWidget);
    expect(find.text('Importación completa'), findsOneWidget);
    expect(find.text('1 canal nuevo'), findsOneWidget);
  });
}
