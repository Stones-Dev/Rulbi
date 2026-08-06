import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/features/sources/source_providers.dart';
import 'package:iptv_app/features/sources/sources_screen.dart';
import 'package:iptv_app/l10n/app_localizations.dart';
import 'package:iptv_core/iptv_core.dart';

import '_helpers/fakes.dart';

/// Gestión de fuentes (ui-spec §2.10, S4 · Ola 3): estado vacío, listado
/// (tipo/contador/última actualización), editar/activar/eliminar. Sin red
/// ni BD real — mismas fakes que el resto de S4.
void main() {
  late FakeSourceRepository sources;
  late FakeSecureCredentialStore secureStore;
  late FakeChannelRepository channels;
  late StreamController<Channel> rawImportController;

  setUp(() {
    sources = FakeSourceRepository();
    secureStore = FakeSecureCredentialStore();
    channels = FakeChannelRepository();
    // Nunca emite ni cierra a propósito: el único test que pulsa
    // "Actualizar" (import_screen sobre una fuente existente) solo
    // comprueba el título inicial, no necesita que el import termine.
    rawImportController = StreamController<Channel>();
  });

  tearDown(() {
    if (!rawImportController.isClosed) rawImportController.close();
  });

  Future<void> pumpScreen(WidgetTester tester, {Locale locale = const Locale('en')}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sourceRepositoryProvider.overrideWithValue(sources),
          secureCredentialStoreProvider.overrideWithValue(secureStore),
          channelRepositoryProvider.overrideWithValue(channels),
          clockProvider.overrideWithValue(FixedClock(DateTime.utc(2026, 8, 6))),
          m3uImportChannelSourceProvider.overrideWithValue(
            FakeImportChannelSource(channels: rawImportController.stream),
          ),
        ],
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: SourcesScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final m3uSource = Source(
    id: 'm3u-1',
    config: M3uUrlSourceConfig(url: Uri.parse('http://host/list.m3u')),
    name: 'Mi lista',
    updatedAt: DateTime.utc(2026, 8, 1),
    lastRefresh: DateTime.utc(2026, 8, 2),
  );

  final xtreamSource = Source(
    id: 'xtream-1',
    config: XtreamSourceConfig(
      host: Uri.parse('http://panel.example:8080'),
      username: 'demo',
    ),
    name: 'Mi panel',
    updatedAt: DateTime.utc(2026, 8, 1),
  );

  testWidgets('estado vacío: invita a añadir la primera fuente', (tester) async {
    await pumpScreen(tester);

    expect(find.text('No sources yet'), findsOneWidget);
    expect(find.text('Add M3U source'), findsOneWidget);
    expect(find.text('Add Xtream source'), findsOneWidget);
  });

  testWidgets(
    'una fila muestra nombre, tipo, nº de canales y última actualización',
    (tester) async {
      await sources.upsert(m3uSource);
      channels.importedChannels.addAll([
        Channel(
          ref: const ChannelRef(sourceId: 'm3u-1', key: 'a'),
          sourceId: 'm3u-1',
          type: ContentType.live,
          name: 'Canal A',
          url: Uri.parse('http://example.com/a'),
        ),
        Channel(
          ref: const ChannelRef(sourceId: 'm3u-1', key: 'b'),
          sourceId: 'm3u-1',
          type: ContentType.live,
          name: 'Canal B',
          url: Uri.parse('http://example.com/b'),
        ),
      ]);

      await pumpScreen(tester);

      expect(find.text('Mi lista'), findsOneWidget);
      expect(find.text('M3U'), findsOneWidget);
      expect(find.text('2 channels'), findsOneWidget);
      expect(find.textContaining('Aug 2, 2026'), findsOneWidget);
    },
  );

  testWidgets('fuente nunca importada muestra "Never imported"', (tester) async {
    await sources.upsert(xtreamSource);
    await pumpScreen(tester);

    expect(find.text('Xtream'), findsOneWidget);
    expect(find.text('Never imported'), findsOneWidget);
  });

  testWidgets('activar/desactivar: el switch escribe Source.withEnabled', (
    tester,
  ) async {
    await sources.upsert(m3uSource);
    await pumpScreen(tester);

    expect(sources.savedSources.single.enabled, isTrue);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(sources.savedSources.single.enabled, isFalse);
  });

  testWidgets('eliminar: confirmación antes de borrar, la fila desaparece', (
    tester,
  ) async {
    await sources.upsert(m3uSource);
    await pumpScreen(tester);

    expect(find.text('Mi lista'), findsOneWidget);

    await tester.tap(find.byKey(const Key('sourceRow.m3u-1.delete')));
    await tester.pumpAndSettle();

    expect(find.text('Delete source?'), findsOneWidget);
    expect(find.text('"Mi lista" and its channels will be removed. This can\'t be undone.'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Mi lista'), findsNothing);
    expect(find.text('No sources yet'), findsOneWidget);
    final tombstoned = await sources.getById('m3u-1');
    expect(tombstoned!.isDeleted, isTrue);
  });

  testWidgets('cancelar el diálogo de borrado no elimina la fuente', (
    tester,
  ) async {
    await sources.upsert(m3uSource);
    await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('sourceRow.m3u-1.delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Mi lista'), findsOneWidget);
    final stillThere = await sources.getById('m3u-1');
    expect(stillThere!.isDeleted, isFalse);
  });

  testWidgets('eliminar una fuente Xtream borra también su secreto (P5)', (
    tester,
  ) async {
    await sources.upsert(xtreamSource);
    await secureStore.save('xtream-1', 'contraseña-original');
    await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('sourceRow.xtream-1.delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(secureStore.secrets, isEmpty);
  });

  testWidgets('eliminar una fuente M3U no toca el almacén seguro', (
    tester,
  ) async {
    await sources.upsert(m3uSource);
    await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('sourceRow.m3u-1.delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(secureStore.secrets, isEmpty);
  });

  testWidgets(
    'editar abre el formulario Xtream precargado sin la contraseña (P5)',
    (tester) async {
      await sources.upsert(xtreamSource);
      await secureStore.save('xtream-1', 'contraseña-original');
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('sourceRow.xtream-1.edit')));
      await tester.pumpAndSettle();

      expect(find.text('Xtream source'), findsOneWidget);
      expect(find.text('Mi panel'), findsOneWidget);
      expect(find.text('demo'), findsOneWidget);
      expect(
        find.text('Leave blank to keep the current password'),
        findsOneWidget,
      );
    },
  );

  testWidgets('refrescar abre ImportScreen sobre la fuente existente', (
    tester,
  ) async {
    await sources.upsert(m3uSource);
    await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('sourceRow.m3u-1.refresh')));
    // No pumpAndSettle: la pantalla de importación queda deliberadamente
    // "en curso" (rawImportController nunca cierra) con un
    // LinearProgressIndicator indeterminado — mismo patrón que
    // import_screen_test.dart.
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }

    expect(find.text('Importing Mi lista'), findsOneWidget);
  });
}
