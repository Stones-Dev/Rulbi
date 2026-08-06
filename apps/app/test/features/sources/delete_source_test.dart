import 'package:iptv_app/features/sources/delete_source.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:test/test.dart';

import '_helpers/fakes.dart';

/// Gestión de fuentes (S4 · Ola 3, ui-spec §2.10). `DeleteSource` tumba
/// (`markDeleted`, ADR-003), nunca hace un `DELETE` real, y borra el
/// secreto del almacén seguro solo para fuentes Xtream (P5 — sin secretos
/// huérfanos).
void main() {
  late FakeSourceRepository sources;
  late FakeSecureCredentialStore secureStore;
  final now = DateTime.utc(2026, 8, 6, 12);

  setUp(() {
    sources = FakeSourceRepository();
    secureStore = FakeSecureCredentialStore();
  });

  DeleteSource makeDeleteSource() => DeleteSource(
    sources: sources,
    secureStore: secureStore,
    clock: FixedClock(now),
  );

  group('M3U (sin secreto)', () {
    test('tumba la fuente y no toca el almacén seguro', () async {
      await sources.upsert(
        Source(
          id: 'm3u-1',
          config: M3uUrlSourceConfig(url: Uri.parse('http://host/list.m3u')),
          name: 'Mi lista',
          updatedAt: DateTime.utc(2026, 8, 1),
        ),
      );
      final deleteSource = makeDeleteSource();

      final result = await deleteSource('m3u-1');

      expect(result, isA<DeleteSourceOk>());
      final tombstoned = sources.savedSources.single;
      expect(tombstoned.isDeleted, isTrue);
      expect(tombstoned.deletedAt, now);
      expect(tombstoned.updatedAt, now);
      expect(secureStore.secrets, isEmpty);
    });
  });

  group('Xtream (con secreto, P5)', () {
    test('tumba la fuente y borra el secreto del almacén seguro', () async {
      await sources.upsert(
        Source(
          id: 'xtream-1',
          config: XtreamSourceConfig(
            host: Uri.parse('http://panel.example:8080'),
            username: 'demo',
          ),
          name: 'Mi panel',
          updatedAt: DateTime.utc(2026, 8, 1),
        ),
      );
      await secureStore.save('xtream-1', 'contraseña-de-prueba');
      final deleteSource = makeDeleteSource();

      final result = await deleteSource('xtream-1');

      expect(result, isA<DeleteSourceOk>());
      final tombstoned = sources.savedSources.single;
      expect(tombstoned.isDeleted, isTrue);
      expect(secureStore.secrets, isEmpty);
    });
  });

  group('casos límite', () {
    test('sourceId inexistente falla sin escribir nada', () async {
      final deleteSource = makeDeleteSource();

      final result = await deleteSource('no-existe');

      expect(
        (result as DeleteSourceFailed).reason,
        DeleteSourceFailureReason.notFound,
      );
      expect(sources.savedSources, isEmpty);
    });

    test('una fuente ya eliminada (tombstone) no se puede volver a borrar', () async {
      await sources.upsert(
        Source(
          id: 'ya-borrada',
          config: M3uUrlSourceConfig(url: Uri.parse('http://host/x.m3u')),
          name: 'Ya borrada',
          updatedAt: DateTime.utc(2026, 8, 1),
          deletedAt: DateTime.utc(2026, 8, 1),
        ),
      );
      final deleteSource = makeDeleteSource();

      final result = await deleteSource('ya-borrada');

      expect(
        (result as DeleteSourceFailed).reason,
        DeleteSourceFailureReason.notFound,
      );
    });

    test('si el upsert del tombstone falla, no se persiste como Lista', () async {
      await sources.upsert(
        Source(
          id: 'm3u-1',
          config: M3uUrlSourceConfig(url: Uri.parse('http://host/list.m3u')),
          name: 'Mi lista',
          updatedAt: DateTime.utc(2026, 8, 1),
        ),
      );
      sources.failUpsert = true;
      final deleteSource = makeDeleteSource();

      final result = await deleteSource('m3u-1');

      expect(
        (result as DeleteSourceFailed).reason,
        DeleteSourceFailureReason.persistFailed,
      );
    });
  });
}
