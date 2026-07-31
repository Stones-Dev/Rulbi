import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_data/iptv_data.dart';
import 'package:iptv_protocols/iptv_protocols.dart';

/// "Ventana y purga EPG" (S2, media): purga de `epg_programmes` fuera de
/// la ventana −1d/+7d. **No hay escritor XMLTV → drift todavía** (esa
/// mitad de la tarea original queda para "ADR-007 + persistencia EPG",
/// Sprint 3 — ver handoff 2026-07-31 y el docstring de `ManageSources`),
/// así que aquí las filas se siembran a mano contra el esquema real, no
/// contra un import real.
void main() {
  late IptvDatabase db;
  late DriftEpgRepository repository;

  setUp(() {
    db = IptvDatabase(NativeDatabase.memory());
    repository = DriftEpgRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seed({
    required String tvgId,
    required DateTime start,
    required DateTime stop,
    String title = 'Programa',
  }) => db
      .into(db.epgProgrammes)
      .insert(
        EpgProgrammesCompanion.insert(
          tvgId: tvgId,
          start: start,
          stop: stop,
          title: title,
        ),
      );

  Future<List<EpgProgrammeRow>> allRows() => db.select(db.epgProgrammes).get();

  final now = DateTime.utc(2026, 3, 10);
  final from = now.subtract(const Duration(days: 1)); // 2026-03-09
  final to = now.add(const Duration(days: 7)); // 2026-03-17

  group('fuera de ventana', () {
    test('un programa entero en el pasado se purga', () async {
      await seed(
        tvgId: 'a',
        start: from.subtract(const Duration(hours: 2)),
        stop: from.subtract(const Duration(hours: 1)),
      );

      final deleted = await repository.purgeOutsideWindow(from: from, to: to);

      expect(deleted, 1);
      expect(await allRows(), isEmpty);
    });

    test('un programa entero en el futuro se purga', () async {
      await seed(
        tvgId: 'a',
        start: to.add(const Duration(hours: 1)),
        stop: to.add(const Duration(hours: 2)),
      );

      final deleted = await repository.purgeOutsideWindow(from: from, to: to);

      expect(deleted, 1);
      expect(await allRows(), isEmpty);
    });
  });

  group('dentro de ventana', () {
    test('un programa que solapa el borde pasado (en emisión) sobrevive', () async {
      await seed(
        tvgId: 'a',
        start: from.subtract(const Duration(hours: 2)),
        stop: from.add(const Duration(hours: 1)),
      );

      final deleted = await repository.purgeOutsideWindow(from: from, to: to);

      expect(deleted, 0);
      expect(await allRows(), hasLength(1));
    });

    test('un programa dentro de la ventana sobrevive', () async {
      await seed(
        tvgId: 'a',
        start: now,
        stop: now.add(const Duration(hours: 1)),
      );

      final deleted = await repository.purgeOutsideWindow(from: from, to: to);

      expect(deleted, 0);
      expect(await allRows(), hasLength(1));
    });
  });

  group('paridad de criterio con XmltvWindow.overlaps (protocols)', () {
    // El parser (T1.3) descarta durante el parseo con `XmltvWindow
    // .overlaps`; la purga debe borrar exactamente lo que ese criterio
    // habría descartado — mismo comportamiento en los dos extremos del
    // pipeline. Se importa el criterio real en vez de reimplementarlo.
    final window = XmltvWindow(from: from, to: to);

    test('sobre los mismos bordes exactos, la purga borra si y solo si '
        'XmltvWindow.overlaps lo habría descartado', () async {
      final cases = <(String, DateTime, DateTime)>[
        ('borde-stop-igual-from', from.subtract(const Duration(hours: 1)), from),
        ('borde-start-igual-to', to, to.add(const Duration(hours: 1))),
        ('empieza-antes-termina-dentro', from.subtract(const Duration(hours: 1)), from.add(const Duration(hours: 1))),
        ('dentro-de-ventana', now, now.add(const Duration(hours: 1))),
      ];

      for (final (tvgId, start, stop) in cases) {
        await seed(tvgId: tvgId, start: start, stop: stop);
      }

      await repository.purgeOutsideWindow(from: from, to: to);

      final survivingIds = (await allRows()).map((r) => r.tvgId).toSet();
      for (final (tvgId, start, stop) in cases) {
        final shouldSurvive = window.overlaps(start: start, stop: stop);
        expect(
          survivingIds.contains(tvgId),
          shouldSurvive,
          reason: '$tvgId: overlaps=$shouldSurvive pero '
              'survives=${survivingIds.contains(tvgId)}',
        );
      }
    });
  });

  group('ventana configurable', () {
    test('con una ventana distinta, cambia el conjunto que sobrevive', () async {
      // Con la ventana por defecto (−1d/+7d) este programa sobrevive
      // (dentro), pero con −7d/+1d queda fuera (empieza dentro de los
      // últimos 7 días pero después de +1d ya no aplica... se elige un
      // caso inequívoco: 3 días en el futuro).
      final start = now.add(const Duration(days: 3));
      final stop = now.add(const Duration(days: 3, hours: 1));
      await seed(tvgId: 'a', start: start, stop: stop);

      final survivesDefaultWindow = await repository.purgeOutsideWindow(
        from: from,
        to: to,
      );
      expect(survivesDefaultWindow, 0);
      expect(await allRows(), hasLength(1));

      final deletedNarrowWindow = await repository.purgeOutsideWindow(
        from: now.subtract(const Duration(days: 7)),
        to: now.add(const Duration(days: 1)),
      );
      expect(deletedNarrowWindow, 1);
      expect(await allRows(), isEmpty);
    });
  });

  group('idempotencia', () {
    test('dos corridas seguidas producen el mismo estado; la segunda no '
        'borra nada', () async {
      await seed(
        tvgId: 'viejo',
        start: from.subtract(const Duration(hours: 2)),
        stop: from.subtract(const Duration(hours: 1)),
      );
      await seed(tvgId: 'vivo', start: now, stop: now.add(const Duration(hours: 1)));

      final first = await repository.purgeOutsideWindow(from: from, to: to);
      expect(first, 1);

      final second = await repository.purgeOutsideWindow(from: from, to: to);
      expect(second, 0);

      final remaining = await allRows();
      expect(remaining, hasLength(1));
      expect(remaining.single.tvgId, 'vivo');
    });
  });
}
