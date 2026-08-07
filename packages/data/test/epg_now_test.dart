import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_data/iptv_data.dart';

/// `EpgRepository.nowAndNextFor` (S5 · Ola 2): carga "ahora/siguiente" por
/// lotes de `tvgId`, para lectura síncrona posterior vía `EpgNowIndex` —
/// ver su docstring y el de `EpgNowIndex` para el porqué (no hay consulta
/// síncrona posible contra SQLite, y una consulta por fila es inviable
/// sobre un listado de 100k canales).
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

  final now = DateTime.utc(2026, 3, 10, 12);

  group('canal sin guía', () {
    test('está ausente del índice (no un null explícito por clave)', () async {
      final index = await repository.nowAndNextFor({'sin-guia'}, now);

      expect(index.nowAiring('sin-guia'), isNull);
      expect(index.nextUp('sin-guia'), isNull);
      expect(index.entries.containsKey('sin-guia'), isFalse);
    });

    test('tvgIds vacío no toca la BD y devuelve un índice vacío', () async {
      final index = await repository.nowAndNextFor(const {}, now);

      expect(index.entries, isEmpty);
      expect(index.at, now);
    });
  });

  group('canal con programa activo', () {
    test('nowAiring devuelve el programa que cubre "at", nextUp el '
        'siguiente por start', () async {
      await seed(
        tvgId: 'a',
        start: now.subtract(const Duration(minutes: 30)),
        stop: now.add(const Duration(minutes: 30)),
        title: 'Ahora',
      );
      await seed(
        tvgId: 'a',
        start: now.add(const Duration(minutes: 30)),
        stop: now.add(const Duration(hours: 1, minutes: 30)),
        title: 'Siguiente',
      );
      await seed(
        tvgId: 'a',
        start: now.add(const Duration(hours: 2)),
        stop: now.add(const Duration(hours: 3)),
        title: 'Después del siguiente',
      );

      final index = await repository.nowAndNextFor({'a'}, now);

      expect(index.nowAiring('a')?.title, 'Ahora');
      expect(index.nextUp('a')?.title, 'Siguiente');
    });
  });

  group('hueco en la guía (instante entre dos programas)', () {
    test('nowAiring es null pero nextUp está presente', () async {
      await seed(
        tvgId: 'a',
        start: now.subtract(const Duration(hours: 2)),
        stop: now.subtract(const Duration(hours: 1)),
        title: 'Ya terminado',
      );
      await seed(
        tvgId: 'a',
        start: now.add(const Duration(hours: 1)),
        stop: now.add(const Duration(hours: 2)),
        title: 'Todavía no',
      );

      final index = await repository.nowAndNextFor({'a'}, now);

      expect(index.nowAiring('a'), isNull);
      expect(index.nextUp('a')?.title, 'Todavía no');
    });
  });

  group('bordes exactos, coherentes con XmltvWindow.overlaps', () {
    test('at == start: el programa cuenta como "ahora" (borde incluido)', () async {
      await seed(
        tvgId: 'a',
        start: now,
        stop: now.add(const Duration(hours: 1)),
        title: 'Empieza justo ahora',
      );

      final index = await repository.nowAndNextFor({'a'}, now);

      expect(index.nowAiring('a')?.title, 'Empieza justo ahora');
    });

    test('at == stop: el programa ya NO cuenta como "ahora" (borde '
        'excluido)', () async {
      await seed(
        tvgId: 'a',
        start: now.subtract(const Duration(hours: 1)),
        stop: now,
        title: 'Termina justo ahora',
      );

      final index = await repository.nowAndNextFor({'a'}, now);

      expect(index.nowAiring('a'), isNull);
      expect(index.nextUp('a'), isNull);
    });
  });

  group('lote grande', () {
    test('más de 500 tvgIds se trocea correctamente', () async {
      final tvgIds = <String>{};
      for (var i = 0; i < 620; i++) {
        final tvgId = 'canal-$i';
        tvgIds.add(tvgId);
        await seed(
          tvgId: tvgId,
          start: now.subtract(const Duration(minutes: 10)),
          stop: now.add(const Duration(minutes: 10)),
          title: 'Programa $i',
        );
      }

      final index = await repository.nowAndNextFor(tvgIds, now);

      expect(index.entries, hasLength(620));
      expect(index.nowAiring('canal-0')?.title, 'Programa 0');
      expect(index.nowAiring('canal-619')?.title, 'Programa 619');
    });
  });

  group('isStaleAt (EpgNowIndex)', () {
    test('false mientras ningún "ahora" cargado ha terminado', () async {
      await seed(
        tvgId: 'a',
        start: now.subtract(const Duration(minutes: 30)),
        stop: now.add(const Duration(minutes: 30)),
      );
      final index = await repository.nowAndNextFor({'a'}, now);

      expect(index.isStaleAt(now.add(const Duration(minutes: 29))), isFalse);
    });

    test('true en cuanto el "ahora" cargado ya terminó', () async {
      await seed(
        tvgId: 'a',
        start: now.subtract(const Duration(minutes: 30)),
        stop: now.add(const Duration(minutes: 30)),
      );
      final index = await repository.nowAndNextFor({'a'}, now);

      expect(index.isStaleAt(now.add(const Duration(minutes: 30))), isTrue);
    });

    test('false si el índice no tenía ningún "ahora" para empezar (solo '
        'huecos/nextUp)', () async {
      await seed(
        tvgId: 'a',
        start: now.add(const Duration(hours: 1)),
        stop: now.add(const Duration(hours: 2)),
      );
      final index = await repository.nowAndNextFor({'a'}, now);

      expect(index.isStaleAt(now.add(const Duration(hours: 5))), isFalse);
    });
  });
}
