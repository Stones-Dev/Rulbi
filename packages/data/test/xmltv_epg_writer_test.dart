import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_data/iptv_data.dart';
import 'package:iptv_protocols/iptv_protocols.dart';

/// Escritor XMLTV→drift (ADR-008, S5 · Ola 2): consume `Stream<XmltvEntry>`
/// (`parseXmltv`, `packages/protocols`) y hace upsert en
/// `epg_programmes`/`epg_channels`. TDD contra el esquema real (P7): sin
/// fixtures de XMLTV crudo aquí — `parseXmltv`/`parseXmltvCore` ya tienen
/// su propia batería de golden files en `packages/protocols/test/`; este
/// escritor se testea contra `XmltvEntry` ya parseado, que es su contrato
/// real de entrada.
void main() {
  late IptvDatabase db;
  late DriftXmltvEpgWriter writer;

  setUp(() {
    db = IptvDatabase(NativeDatabase.memory());
    writer = DriftXmltvEpgWriter(db);
  });

  tearDown(() async {
    await db.close();
  });

  final now = DateTime.utc(2026, 3, 10);

  EpgProgramme programme({
    required String tvgId,
    required DateTime start,
    String title = 'Programa',
    String? description,
  }) => EpgProgramme(
    tvgId: tvgId,
    start: start,
    stop: start.add(const Duration(hours: 1)),
    title: title,
    description: description,
  );

  Future<List<EpgProgrammeRow>> allProgrammes() =>
      db.select(db.epgProgrammes).get();
  Future<List<EpgChannelRow>> allChannels() => db.select(db.epgChannels).get();

  group('programas nuevos', () {
    test('inserta programas y cuenta programmesInserted', () async {
      final start1 = now;
      final start2 = now.add(const Duration(hours: 2));
      final entries = Stream.fromIterable([
        XmltvProgrammeEntry(programme(tvgId: 'a', start: start1)),
        XmltvProgrammeEntry(programme(tvgId: 'a', start: start2)),
      ]);

      final stats = await writer.write(entries, now: now);

      expect(stats.programmesInserted, 2);
      expect(stats.programmesUpdated, 0);
      expect(stats.programmesUnchanged, 0);
      expect(stats.duplicateKeys, 0);
      expect(await allProgrammes(), hasLength(2));
    });
  });

  group('duplicados dentro del mismo XMLTV (ADR-008 §Decisión 3)', () {
    test(
      'la misma (tvgId, start) repetida en el stream: gana el título de la '
      'última entrada, no solo "no lanza"',
      () async {
        final start = now;
        final entries = Stream.fromIterable([
          XmltvProgrammeEntry(
            programme(tvgId: 'a', start: start, title: 'Primera versión'),
          ),
          XmltvProgrammeEntry(
            programme(tvgId: 'a', start: start, title: 'Última versión'),
          ),
        ]);

        final stats = await writer.write(entries, now: now);

        expect(stats.duplicateKeys, 1);
        final rows = await allProgrammes();
        expect(rows, hasLength(1));
        expect(rows.single.title, 'Última versión');
      },
    );

    test(
      'lo mismo para XmltvChannelEntry duplicado por tvgId',
      () async {
        final entries = Stream.fromIterable([
          const XmltvChannelEntry(
            XmltvChannel(id: 'canal.1', displayNames: ['Nombre viejo']),
          ),
          const XmltvChannelEntry(
            XmltvChannel(id: 'canal.1', displayNames: ['Nombre nuevo']),
          ),
        ]);

        final stats = await writer.write(entries, now: now);

        expect(stats.duplicateKeys, 1);
        final rows = await allChannels();
        expect(rows, hasLength(1));
        expect(rows.single.displayNamesJson, '["Nombre nuevo"]');
      },
    );
  });

  group('pisado entre imports sucesivos (ADR-008 §Decisión 1)', () {
    test(
      'un segundo import sobre la misma (tvgId, start) sobreescribe al '
      'primero — gana el segundo',
      () async {
        final start = now;
        await writer.write(
          Stream.fromIterable([
            XmltvProgrammeEntry(
              programme(tvgId: 'a', start: start, title: 'Fuente 1'),
            ),
          ]),
          now: now,
        );
        final secondStats = await writer.write(
          Stream.fromIterable([
            XmltvProgrammeEntry(
              programme(tvgId: 'a', start: start, title: 'Fuente 2'),
            ),
          ]),
          now: now,
        );

        expect(secondStats.programmesUpdated, 1);
        expect(secondStats.programmesInserted, 0);
        final rows = await allProgrammes();
        expect(rows, hasLength(1));
        expect(rows.single.title, 'Fuente 2');
      },
    );

    test(
      'un segundo import idéntico no genera updates — programmesUnchanged',
      () async {
        Stream<XmltvEntry> sameEntries() => Stream.fromIterable([
          XmltvProgrammeEntry(programme(tvgId: 'a', start: now)),
        ]);

        await writer.write(sameEntries(), now: now);
        final secondStats = await writer.write(sameEntries(), now: now);

        expect(secondStats.programmesInserted, 0);
        expect(secondStats.programmesUpdated, 0);
        expect(secondStats.programmesUnchanged, 1);
      },
    );
  });

  group('canales de guía (ADR-008 §Decisión 2)', () {
    test(
      'XmltvChannelEntry con varios display-names, sin icon/urls: '
      'round-trip correcto',
      () async {
        const channel = XmltvChannel(
          id: 'canal.1',
          displayNames: ['Canal Uno', 'Channel One'],
        );

        final stats = await writer.write(
          Stream.fromIterable([const XmltvChannelEntry(channel)]),
          now: now,
        );

        expect(stats.channelsInserted, 1);
        final rows = await allChannels();
        expect(rows.single.tvgId, 'canal.1');
        expect(rows.single.displayNamesJson, '["Canal Uno","Channel One"]');
        expect(rows.single.icon, isNull);
        expect(rows.single.urlsJson, '[]');
      },
    );

    test('con icon y urls: se persisten', () async {
      final channel = XmltvChannel(
        id: 'canal.2',
        displayNames: const ['Canal Dos'],
        icon: Uri.parse('http://example.com/icon.png'),
        urls: [Uri.parse('http://example.com/stream')],
      );

      await writer.write(
        Stream.fromIterable([XmltvChannelEntry(channel)]),
        now: now,
      );

      final row = (await allChannels()).single;
      expect(row.icon, 'http://example.com/icon.png');
      expect(row.urlsJson, '["http://example.com/stream"]');
    });
  });

  group('stream que falla a mitad', () {
    test('no queda un lote a medias: nada se escribe', () async {
      final entries = Stream<XmltvEntry>.fromFuture(
        Future.error(StateError('fallo simulado del parser')),
      );

      await expectLater(
        () => writer.write(entries, now: now),
        throwsA(isA<StateError>()),
      );
      expect(await allProgrammes(), isEmpty);
      expect(await allChannels(), isEmpty);
    });

    test(
      'un fallo tras el primer lote no dinamita ese lote ya confirmado',
      () async {
        // `batchSize: 3` (en vez de los 500 reales) para cruzar un límite
        // de lote con un número pequeño y determinista de entradas — un
        // generador `async*` entrega cada elemento solo cuando el
        // consumidor lo pide, así que no hay ninguna carrera de
        // temporizadores que ganar: el tercer elemento dispara el
        // `flush()` (que se completa entero, transacción incluida, antes
        // de que el `await for` pida el cuarto), y solo entonces el
        // generador lanza.
        final smallBatchWriter = DriftXmltvEpgWriter(db, batchSize: 3);

        Stream<XmltvEntry> entriesThenFail() async* {
          for (var i = 0; i < 3; i++) {
            yield XmltvProgrammeEntry(
              programme(tvgId: 'a$i', start: now.add(Duration(hours: i))),
            );
          }
          throw StateError('fallo simulado a mitad');
        }

        await expectLater(
          () => smallBatchWriter.write(entriesThenFail(), now: now),
          throwsA(isA<StateError>()),
        );
        expect(await allProgrammes(), hasLength(3));
      },
    );
  });
}
