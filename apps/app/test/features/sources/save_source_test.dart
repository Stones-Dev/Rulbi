import 'package:iptv_app/features/sources/save_source.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:test/test.dart';

import '_helpers/fakes.dart';

/// S4 · Ola 2. `SaveSource` no llama a `ManageSources.addSource` (eso
/// exige un `Stream<Channel>`, Ola 3) — solo registra la fuente.
void main() {
  late FakeSourceRepository sources;
  late FakeSecureCredentialStore secureStore;
  final now = DateTime.utc(2026, 8, 5, 12);

  setUp(() {
    sources = FakeSourceRepository();
    secureStore = FakeSecureCredentialStore();
  });

  SaveSource makeSaveSource({String id = 'fixed-id'}) => SaveSource(
    sources: sources,
    secureStore: secureStore,
    clock: FixedClock(now),
    generateId: () => id,
  );

  group('fuente sin secreto (M3U)', () {
    test('guarda la fuente con lastRefresh null y no toca el almacén seguro', () async {
      final saveSource = makeSaveSource();

      final result = await saveSource(
        name: 'Mi lista',
        config: M3uUrlSourceConfig(url: Uri.parse('http://host/list.m3u')),
        refreshPolicy: SourceRefreshPolicy.manual,
      );

      expect(result, isA<SaveSourceOk>());
      final source = (result as SaveSourceOk).source;
      expect(source.id, 'fixed-id');
      expect(source.name, 'Mi lista');
      expect(source.lastRefresh, isNull);
      expect(source.updatedAt, now);
      expect(sources.savedSources, [source]);
      expect(secureStore.secrets, isEmpty);
    });
  });

  group('fuente con secreto (Xtream)', () {
    test(
      'guarda el secreto ANTES que la fuente, y la contraseña nunca entra en Source',
      () async {
        final saveSource = makeSaveSource();

        final result = await saveSource(
          name: 'Mi panel',
          config: XtreamSourceConfig(
            host: Uri.parse('http://panel.example:8080'),
            username: 'demo',
          ),
          refreshPolicy: SourceRefreshPolicy.onOpen,
          secret: 'contraseña-real',
        );

        expect(result, isA<SaveSourceOk>());
        expect(secureStore.secrets['fixed-id'], 'contraseña-real');
        final source = (result as SaveSourceOk).source;
        expect(source.toString(), isNot(contains('contraseña-real')));
      },
    );

    test(
      'si el upsert falla tras guardar el secreto, lo borra (compensación, sin secretos huérfanos)',
      () async {
        sources.failUpsert = true;
        final saveSource = makeSaveSource();

        final result = await saveSource(
          name: 'Mi panel',
          config: XtreamSourceConfig(
            host: Uri.parse('http://panel.example:8080'),
            username: 'demo',
          ),
          refreshPolicy: SourceRefreshPolicy.manual,
          secret: 'contraseña-real',
        );

        expect(
          (result as SaveSourceFailed).reason,
          SaveSourceFailureReason.persistFailed,
        );
        expect(secureStore.secrets, isEmpty);
      },
    );

    test('si el almacén seguro falla, no se persiste ninguna fuente', () async {
      secureStore.failSave = true;
      final saveSource = makeSaveSource();

      final result = await saveSource(
        name: 'Mi panel',
        config: XtreamSourceConfig(
          host: Uri.parse('http://panel.example:8080'),
          username: 'demo',
        ),
        refreshPolicy: SourceRefreshPolicy.manual,
        secret: 'contraseña-real',
      );

      expect(
        (result as SaveSourceFailed).reason,
        SaveSourceFailureReason.secretStoreFailed,
      );
      expect(sources.savedSources, isEmpty);
    });
  });

  group('nombre duplicado', () {
    test('rechaza un nombre ya usado por otra fuente viva', () async {
      await sources.upsert(
        Source(
          id: 'otra',
          config: M3uUrlSourceConfig(url: Uri.parse('http://host/a.m3u')),
          name: 'Mi Lista',
          updatedAt: now,
        ),
      );
      final saveSource = makeSaveSource();

      final result = await saveSource(
        name: 'mi lista', // mismo nombre, distinta capitalización
        config: M3uUrlSourceConfig(url: Uri.parse('http://host/b.m3u')),
        refreshPolicy: SourceRefreshPolicy.manual,
      );

      expect(
        (result as SaveSourceFailed).reason,
        SaveSourceFailureReason.duplicateName,
      );
    });

    test('un nombre igual al de una fuente ya eliminada (tombstone) sí se permite', () async {
      await sources.upsert(
        Source(
          id: 'otra',
          config: M3uUrlSourceConfig(url: Uri.parse('http://host/a.m3u')),
          name: 'Mi Lista',
          updatedAt: now,
          deletedAt: now,
        ),
      );
      final saveSource = makeSaveSource();

      final result = await saveSource(
        name: 'Mi Lista',
        config: M3uUrlSourceConfig(url: Uri.parse('http://host/b.m3u')),
        refreshPolicy: SourceRefreshPolicy.manual,
      );

      expect(result, isA<SaveSourceOk>());
    });
  });
}
