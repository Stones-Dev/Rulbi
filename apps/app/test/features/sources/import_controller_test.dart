import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iptv_app/features/sources/import_controller.dart';
import 'package:iptv_app/features/sources/probe_result.dart';
import 'package:iptv_app/features/sources/source_providers.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_protocols/iptv_protocols.dart';
import 'package:test/test.dart';

import '_helpers/fakes.dart';

/// Motor de importación (S4 · Ola 3, ui-spec §2.14): conecta el
/// `Stream<Channel>` de [ImportChannelSource] con
/// `ManageSources.addSource`/`refreshSource`, sin red ni isolates reales —
/// [FakeImportChannelSource] sustituye a `parseM3u`/`XtreamClient
/// .importChannels()`, y [FakeChannelRepository] a `DriftChannelRepository`
/// (con la misma semántica de "todo o nada" que la transacción real de
/// drift: solo "confirma" los canales importados si el stream no falla).
void main() {
  Channel channel(String refKey) => Channel(
    ref: ChannelRef(sourceId: 's1', key: refKey),
    sourceId: 's1',
    type: ContentType.live,
    name: 'Canal $refKey',
    url: Uri.parse('http://example.com/$refKey'),
  );

  ProviderContainer buildContainer({
    required FakeSourceRepository sources,
    required FakeChannelRepository channels,
    FakeSecureCredentialStore? secureStore,
    required ImportChannelSource m3uSource,
    ImportChannelSource? xtreamSource,
    int progressEvery = 250,
    Duration progressInterval = const Duration(days: 1),
    DateTime? now,
  }) {
    final container = ProviderContainer(
      overrides: [
        sourceRepositoryProvider.overrideWithValue(sources),
        channelRepositoryProvider.overrideWithValue(channels),
        secureCredentialStoreProvider.overrideWithValue(
          secureStore ?? FakeSecureCredentialStore(),
        ),
        clockProvider.overrideWithValue(FixedClock(now ?? DateTime.utc(2026, 8, 6))),
        m3uImportChannelSourceProvider.overrideWithValue(m3uSource),
        xtreamImportChannelSourceProvider.overrideWithValue(xtreamSource ?? m3uSource),
        importControllerProvider.overrideWith(
          () => ImportController(
            progressEvery: progressEvery,
            progressInterval: progressInterval,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Source newM3uSource({String id = 's1', DateTime? lastRefresh}) => Source(
    id: id,
    config: M3uUrlSourceConfig(url: Uri.parse('http://host/list.m3u')),
    name: 'Mi lista',
    updatedAt: DateTime.utc(2026, 8, 1),
    lastRefresh: lastRefresh,
  );

  group('alta (addSource, lastRefresh == null)', () {
    test('progreso incremental cada progressEvery canales', () async {
      final sources = FakeSourceRepository();
      final channelsRepo = FakeChannelRepository();
      final importSource = FakeImportChannelSource(
        channels: Stream.fromIterable([
          channel('a'),
          channel('b'),
          channel('c'),
          channel('d'),
          channel('e'),
        ]),
      );
      final container = buildContainer(
        sources: sources,
        channels: channelsRepo,
        m3uSource: importSource,
        progressEvery: 2,
      );

      final history = <ImportState>[];
      container.listen(importControllerProvider, (_, next) => history.add(next));

      await container.read(importControllerProvider.notifier).start(newM3uSource());

      final runningStates = history.whereType<ImportRunning>().toList();
      expect(runningStates.first.channelsSeen, 0); // publicado al arrancar
      expect(runningStates.map((s) => s.channelsSeen), containsAll([0, 2, 4]));
      expect(history.last, isA<ImportDone>());
    });

    test(
      'ImportDone con SourceImportStats real e informe reutilizado sin '
      'reinventar campos',
      () async {
        final sources = FakeSourceRepository();
        final channelsRepo = FakeChannelRepository();
        const report = ImportReport(
          parsed: 3,
          discarded: [
            DiscardedLine(lineNumber: 7, rawLine: '#broken', reason: 'malformed'),
          ],
        );
        final importSource = FakeImportChannelSource(
          channels: Stream.fromIterable([channel('a'), channel('b'), channel('c')]),
          summary: const M3uImportSummary(report),
        );
        final container = buildContainer(
          sources: sources,
          channels: channelsRepo,
          m3uSource: importSource,
        );

        await container.read(importControllerProvider.notifier).start(newM3uSource());

        final done = container.read(importControllerProvider) as ImportDone;
        expect(done.stats.inserted, 3);
        expect(channelsRepo.importedChannels, hasLength(3));
        final summary = done.summary as M3uImportSummary;
        expect(summary.report, same(report));
        expect(done.summary.discardedCount, 1);
      },
    );

    test(
      'error a mitad de stream → ImportFailed con motivo tipado, nada '
      'confirmado en el repositorio',
      () async {
        final sources = FakeSourceRepository();
        final channelsRepo = FakeChannelRepository();
        final importSource = FakeImportChannelSource(
          channels: Stream<Channel>.multi((controller) {
            controller.add(channel('a'));
            controller.add(channel('b'));
            controller.addError(const SocketException('caída de red'));
            controller.close();
          }),
        );
        final container = buildContainer(
          sources: sources,
          channels: channelsRepo,
          m3uSource: importSource,
        );

        await container.read(importControllerProvider.notifier).start(newM3uSource());

        final failed = container.read(importControllerProvider) as ImportFailed;
        expect(failed.reason, ProbeFailureReason.network);
        expect(failed.channelsSeen, 2);
        expect(channelsRepo.importedChannels, isEmpty);
      },
    );
  });

  group('refresco (refreshSource, fuente ya existente)', () {
    test('cancelación: nada se confirma en el repositorio de canales', () async {
      final existing = newM3uSource(lastRefresh: DateTime.utc(2026, 8, 2));
      final sources = FakeSourceRepository();
      await sources.upsert(existing);
      final channelsRepo = FakeChannelRepository();
      final rawController = StreamController<Channel>();
      addTearDown(() {
        if (!rawController.isClosed) rawController.close();
      });
      final importSource = FakeImportChannelSource(channels: rawController.stream);
      final container = buildContainer(
        sources: sources,
        channels: channelsRepo,
        m3uSource: importSource,
      );

      final notifier = container.read(importControllerProvider.notifier);
      final future = notifier.start(existing);

      rawController.add(channel('a'));
      await Future<void>.delayed(Duration.zero);
      notifier.cancel();
      await future;

      expect(container.read(importControllerProvider), isA<ImportCancelled>());
      expect(channelsRepo.importedChannels, isEmpty);
      // refreshSource solo hace upsert del Source si importSourceContent
      // termina con éxito — al cancelar, la fuente queda exactamente como
      // estaba (mismo lastRefresh de antes).
      expect(sources.savedSources.single.lastRefresh, existing.lastRefresh);
    });

    test('refresco sobre fuente existente llama a refreshSource, no a addSource', () async {
      final existing = newM3uSource(lastRefresh: DateTime.utc(2026, 8, 2));
      final sources = FakeSourceRepository();
      await sources.upsert(existing);
      final channelsRepo = FakeChannelRepository();
      final importSource = FakeImportChannelSource(
        channels: Stream.fromIterable([channel('a')]),
      );
      final container = buildContainer(
        sources: sources,
        channels: channelsRepo,
        m3uSource: importSource,
      );

      await container.read(importControllerProvider.notifier).start(existing);

      expect(channelsRepo.importCalls, 1);
      // El id no cambia (mismo objeto Source pasado): un refresco upsertea
      // la MISMA fila, nunca crea una fuente nueva.
      expect(sources.savedSources, hasLength(1));
      expect(sources.savedSources.single.id, existing.id);
    });
  });

  group('descartes tolerados', () {
    test('líneas rotas no impiden un import correcto (con incidencias)', () async {
      final sources = FakeSourceRepository();
      final channelsRepo = FakeChannelRepository();
      const report = ImportReport(
        parsed: 2,
        discarded: [
          DiscardedLine(lineNumber: 3, rawLine: '#EXTINF', reason: 'sin URL'),
        ],
      );
      final importSource = FakeImportChannelSource(
        channels: Stream.fromIterable([channel('a'), channel('b')]),
        summary: const M3uImportSummary(report),
      );
      final container = buildContainer(
        sources: sources,
        channels: channelsRepo,
        m3uSource: importSource,
      );

      await container.read(importControllerProvider.notifier).start(newM3uSource());

      final done = container.read(importControllerProvider) as ImportDone;
      expect(done.stats.inserted, 2);
      expect(done.summary.discardedCount, 1);
    });
  });
}
