import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/features/sources/m3u_probe.dart';
import 'package:iptv_app/features/sources/m3u_source_form.dart';
import 'package:iptv_app/features/sources/probe_result.dart';
import 'package:iptv_app/features/sources/save_source.dart';
import 'package:iptv_app/features/sources/source_providers.dart';
import 'package:iptv_core/iptv_core.dart';

import '_helpers/fakes.dart';
import '_helpers/form_harness.dart';

/// S4 · Ola 2, Formulario M3U (ui-spec §2.8). TDD: escrito antes de
/// terminar de ajustar `m3u_source_form.dart` a estos casos — cubre
/// render, validación i18n en/es, Probar (éxito/fallo) y Guardar
/// (éxito/fallo), sin llamar nunca a `ManageSources.addSource` (Ola 3).
void main() {
  late FakeSourceRepository sources;
  late FakeSecureCredentialStore secureStore;

  setUp(() {
    sources = FakeSourceRepository();
    secureStore = FakeSecureCredentialStore();
  });

  List<Override> overridesWith({
    ProbeResult<M3uProbeSummary>? probeResult,
  }) => [
    saveSourceProvider.overrideWithValue(
      SaveSource(
        sources: sources,
        secureStore: secureStore,
        clock: FixedClock(DateTime.utc(2026, 8, 6)),
        generateId: () => 'm3u-1',
      ),
    ),
    if (probeResult != null)
      m3uProbeProvider.overrideWithValue(FakeM3uProbe(probeResult)),
  ];

  Future<void> fillRequiredFields(WidgetTester tester, {String name = 'Mi lista'}) async {
    await tester.enterText(
      find.byKey(M3uSourceForm.nameFieldKey),
      name,
    );
    await tester.enterText(
      find.byKey(M3uSourceForm.urlFieldKey),
      'http://host/list.m3u',
    );
  }

  testWidgets('renderiza todos los campos de ui-spec §2.8', (tester) async {
    await pumpSourceForm(tester, const M3uSourceForm(), overrides: overridesWith());

    expect(find.byKey(M3uSourceForm.nameFieldKey), findsOneWidget);
    expect(find.byKey(M3uSourceForm.originSegmentKey), findsOneWidget);
    expect(find.byKey(M3uSourceForm.urlFieldKey), findsOneWidget);
    expect(find.byKey(M3uSourceForm.epgUrlFieldKey), findsOneWidget);
    expect(find.text('Advanced'), findsOneWidget);
    expect(find.text('Automatic update'), findsOneWidget);
    expect(find.text('Test'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('el campo Archivo y el botón de selección aparecen al elegir origen Archivo', (
    tester,
  ) async {
    await pumpSourceForm(tester, const M3uSourceForm(), overrides: overridesWith());

    expect(find.byKey(M3uSourceForm.urlFieldKey), findsOneWidget);
    expect(find.byKey(M3uSourceForm.fileFieldKey), findsNothing);

    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();

    expect(find.byKey(M3uSourceForm.urlFieldKey), findsNothing);
    expect(find.byKey(M3uSourceForm.fileFieldKey), findsOneWidget);
    expect(find.byKey(M3uSourceForm.pickFileButtonKey), findsOneWidget);
  });

  group('validación — nombre vacío', () {
    testWidgets('en: muestra el error i18n en inglés', (tester) async {
      await pumpSourceForm(tester, const M3uSourceForm(), overrides: overridesWith());
      await tester.enterText(find.byKey(M3uSourceForm.urlFieldKey), 'http://host/list.m3u');

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(fieldError('Enter a name'), findsOneWidget);
    });

    testWidgets('es: muestra el error i18n en español', (tester) async {
      await pumpSourceForm(
        tester,
        const M3uSourceForm(),
        locale: const Locale('es'),
        overrides: overridesWith(),
      );
      await tester.enterText(find.byKey(M3uSourceForm.urlFieldKey), 'http://host/list.m3u');

      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(fieldError('Introduce un nombre'), findsOneWidget);
    });
  });

  testWidgets('validación — URL vacía: error i18n', (tester) async {
    await pumpSourceForm(tester, const M3uSourceForm(), overrides: overridesWith());
    await tester.enterText(find.byKey(M3uSourceForm.nameFieldKey), 'Mi lista');

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(fieldError('Enter the playlist URL'), findsOneWidget);
  });

  testWidgets('validación — URL sin esquema http(s): error i18n', (tester) async {
    await pumpSourceForm(tester, const M3uSourceForm(), overrides: overridesWith());
    await tester.enterText(find.byKey(M3uSourceForm.nameFieldKey), 'Mi lista');
    await tester.enterText(find.byKey(M3uSourceForm.urlFieldKey), 'ftp://host/list.m3u');

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(fieldError('Enter a valid http(s) URL'), findsOneWidget);
  });

  testWidgets('validación — origen Archivo sin archivo elegido: error i18n', (tester) async {
    await pumpSourceForm(tester, const M3uSourceForm(), overrides: overridesWith());
    await tester.enterText(find.byKey(M3uSourceForm.nameFieldKey), 'Mi lista');
    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(fieldError('Choose an .m3u/.m3u8 file'), findsOneWidget);
  });

  testWidgets('validación — EPG URL inválida (opcional pero mal formada): error i18n', (
    tester,
  ) async {
    await pumpSourceForm(tester, const M3uSourceForm(), overrides: overridesWith());
    await fillRequiredFields(tester);
    await tester.enterText(find.byKey(M3uSourceForm.epgUrlFieldKey), 'no-es-una-url');

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(fieldError('Enter a valid http(s) URL'), findsWidgets);
  });

  group('Probar', () {
    testWidgets('éxito: muestra el nº de canales de la muestra', (tester) async {
      await pumpSourceForm(
        tester,
        const M3uSourceForm(),
        overrides: overridesWith(
          probeResult: const ProbeOk(M3uProbeSummary(channelCount: 5, discardedCount: 0)),
        ),
      );
      await fillRequiredFields(tester);

      await tester.tap(find.text('Test'));
      await tester.pumpAndSettle();

      expect(find.text('5 channels found in the sample'), findsOneWidget);
    });

    testWidgets('éxito con descartes: muestra también la nota de entradas ignoradas', (
      tester,
    ) async {
      await pumpSourceForm(
        tester,
        const M3uSourceForm(),
        overrides: overridesWith(
          probeResult: const ProbeOk(M3uProbeSummary(channelCount: 3, discardedCount: 2)),
        ),
      );
      await fillRequiredFields(tester);

      await tester.tap(find.text('Test'));
      await tester.pumpAndSettle();

      expect(find.text('2 entries ignored'), findsOneWidget);
    });

    testWidgets('fallo: muestra el mensaje i18n del motivo', (tester) async {
      await pumpSourceForm(
        tester,
        const M3uSourceForm(),
        overrides: overridesWith(
          probeResult: const ProbeFailed(ProbeFailureReason.notFound),
        ),
      );
      await fillRequiredFields(tester);

      await tester.tap(find.text('Test'));
      await tester.pumpAndSettle();

      expect(find.text('Not found (404).'), findsOneWidget);
    });

    testWidgets('no dispara la petición si la URL es inválida', (tester) async {
      final probe = FakeM3uProbe(
        const ProbeOk(M3uProbeSummary(channelCount: 1, discardedCount: 0)),
      );
      await pumpSourceForm(
        tester,
        const M3uSourceForm(),
        overrides: [
          ...overridesWith(),
          m3uProbeProvider.overrideWithValue(probe),
        ],
      );
      await tester.enterText(find.byKey(M3uSourceForm.nameFieldKey), 'Mi lista');

      await tester.tap(find.text('Test'));
      await tester.pumpAndSettle();

      expect(probe.lastProbedUrl, isNull);
      expect(fieldError('Enter the playlist URL'), findsOneWidget);
    });
  });

  group('Guardar', () {
    testWidgets('envío correcto: llama a SaveSource con el M3uUrlSourceConfig exacto, hace pop y muestra snackbar', (
      tester,
    ) async {
      await pumpSourceForm(tester, const M3uSourceForm(), overrides: overridesWith());
      await fillRequiredFields(tester, name: 'Mi lista');
      await tester.enterText(
        find.byKey(M3uSourceForm.epgUrlFieldKey),
        'http://host/guide.xml.gz',
      );
      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(M3uSourceForm.userAgentFieldKey), 'MiAgente/2.0');

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(sources.savedSources, hasLength(1));
      final saved = sources.savedSources.single;
      expect(saved.name, 'Mi lista');
      expect(saved.lastRefresh, isNull);
      final config = saved.config as M3uUrlSourceConfig;
      expect(config.url, Uri.parse('http://host/list.m3u'));
      expect(config.epgUrl, Uri.parse('http://host/guide.xml.gz'));
      expect(config.userAgent, 'MiAgente/2.0');

      expect(find.byKey(M3uSourceForm.nameFieldKey), findsNothing);
      expect(find.byKey(openButtonKey), findsOneWidget);
      expect(find.text('Source "Mi lista" saved'), findsOneWidget);
    });

    testWidgets('envío con origen Archivo: llama a SaveSource con M3uFileSourceConfig', (
      tester,
    ) async {
      await pumpSourceForm(
        tester,
        M3uSourceForm(pickFile: () async => 'C:/listas/mi_lista.m3u'),
        overrides: overridesWith(),
      );
      await tester.enterText(find.byKey(M3uSourceForm.nameFieldKey), 'Mi lista de archivo');
      await tester.tap(find.text('File'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(M3uSourceForm.pickFileButtonKey));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final saved = sources.savedSources.single;
      final config = saved.config as M3uFileSourceConfig;
      expect(config.filePath, 'C:/listas/mi_lista.m3u');
    });

    testWidgets('nombre duplicado: muestra el error i18n y no navega atrás', (tester) async {
      await sources.upsert(
        Source(
          id: 'existente',
          config: M3uUrlSourceConfig(url: Uri.parse('http://host/otra.m3u')),
          name: 'Mi lista',
          updatedAt: DateTime.utc(2026, 8, 1),
        ),
      );
      await pumpSourceForm(tester, const M3uSourceForm(), overrides: overridesWith());
      await fillRequiredFields(tester, name: 'Mi lista');

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('A source with this name already exists'), findsOneWidget);
      expect(find.byKey(M3uSourceForm.nameFieldKey), findsOneWidget);
    });
  });
}
