import 'package:iptv_app/features/epg/epg_ingest.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_protocols/iptv_protocols.dart';
import 'package:test/test.dart';

import '../sources/_helpers/fakes.dart';

/// `AppEpgIngestPort` (S5.5, Bloque B4) — compone `EpgSource` +
/// `XmltvEpgWriter`, mismo par que `ImportController._runEpgPhase`.
/// Reutiliza `FakeEpgSource`/`FakeXmltvEpgWriter` de
/// `features/sources/_helpers/fakes.dart` (ya escritos para el import
/// manual de S5 · Ola 2) en vez de duplicarlos.
void main() {
  final now = DateTime.utc(2026, 8, 7);

  Source source() => Source(
    id: 's1',
    config: M3uUrlSourceConfig(url: Uri.parse('http://example.com/list.m3u')),
    name: 'Mi lista',
    updatedAt: now,
  );

  test('fuente sin guía (epgFor -> null) -> null, sin tocar el escritor', () async {
    final epgSource = FakeEpgSource();
    final writer = FakeXmltvEpgWriter();
    final ingest = AppEpgIngestPort(epgSource: epgSource, writer: writer);

    final stats = await ingest.ingestFor(source(), now: now);

    expect(stats, isNull);
    expect(writer.writeCalls, 0);
  });

  test('fuente con guía -> escribe vía el escritor y devuelve sus stats', () async {
    const expectedStats = EpgImportStats(
      programmesInserted: 5,
      programmesUpdated: 1,
      programmesUnchanged: 0,
      channelsInserted: 0,
      channelsUpdated: 0,
      channelsUnchanged: 0,
      duplicateKeys: 0,
    );
    final entry = XmltvProgrammeEntry(
      EpgProgramme(tvgId: 'c1', start: now, stop: now.add(const Duration(hours: 1)), title: 'Programa'),
    );
    final epgSource = FakeEpgSource(
      outcome: XmltvParseOutcome(entries: Stream.value(entry), report: Future.value(_emptyReport())),
    );
    final writer = FakeXmltvEpgWriter(stats: expectedStats);
    final ingest = AppEpgIngestPort(epgSource: epgSource, writer: writer);

    final stats = await ingest.ingestFor(source(), now: now);

    expect(stats, expectedStats);
    expect(writer.writeCalls, 1);
    expect(writer.written, [entry]);
  });

  test('si entries falla, el error se propaga y report.ignore() evita la excepción sin manejar', () async {
    final epgSource = FakeEpgSource(
      outcomeBuilder: () => XmltvParseOutcome(
        entries: Stream<XmltvEntry>.fromFuture(Future.error(StateError('fallo de red'))),
        report: Future<XmltvImportReport>.error(StateError('fallo de red')),
      ),
    );
    final writer = FakeXmltvEpgWriter();
    final ingest = AppEpgIngestPort(epgSource: epgSource, writer: writer);

    await expectLater(() => ingest.ingestFor(source(), now: now), throwsStateError);
  });
}

XmltvImportReport _emptyReport() => const XmltvImportReport(
  parsedChannels: 0,
  parsedProgrammes: 0,
  outOfWindowProgrammes: 0,
  assumedUtcDates: 0,
  unknownChannelRefs: {},
  unknownTags: {},
  discardedCount: 0,
  discarded: [],
  discardedTruncated: false,
);
