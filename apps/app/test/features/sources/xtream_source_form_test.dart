import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/features/sources/probe_result.dart';
import 'package:iptv_app/features/sources/save_source.dart';
import 'package:iptv_app/features/sources/source_providers.dart';
import 'package:iptv_app/features/sources/xtream_probe.dart';
import 'package:iptv_app/features/sources/xtream_source_form.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_protocols/iptv_protocols.dart';

import '_helpers/fakes.dart';
import '_helpers/form_harness.dart';

/// S4 · Ola 2, Formulario Xtream (ui-spec §2.9, ADR-006). TDD: cubre
/// render, validación i18n en/es (incluida la del host normalizado vía
/// `normalizeXtreamPanelHost`), Probar conexión (éxito/fallo) y Guardar
/// (éxito/fallo/nombre duplicado), más un grupo P5 dedicado a que la
/// contraseña nunca se filtre — mismo espíritu que el grupo
/// "P5 — anti-fuga de credenciales" de T1.4 en `packages/protocols`.
void main() {
  late FakeSourceRepository sources;
  late FakeSecureCredentialStore secureStore;

  setUp(() {
    sources = FakeSourceRepository();
    secureStore = FakeSecureCredentialStore();
  });

  List<Override> overridesWith({ProbeResult<XtreamProbeSummary>? probeResult}) => [
    saveSourceProvider.overrideWithValue(
      SaveSource(
        sources: sources,
        secureStore: secureStore,
        clock: FixedClock(DateTime.utc(2026, 8, 6)),
        generateId: () => 'xtream-1',
      ),
    ),
    if (probeResult != null)
      xtreamProbeProvider.overrideWithValue(FakeXtreamProbe(probeResult)),
  ];

  Future<void> fillRequiredFields(WidgetTester tester, {String name = 'Mi panel'}) async {
    await tester.enterText(find.byKey(XtreamSourceForm.nameFieldKey), name);
    await tester.enterText(
      find.byKey(XtreamSourceForm.hostFieldKey),
      'panel.example:8080',
    );
    await tester.enterText(find.byKey(XtreamSourceForm.usernameFieldKey), 'demo');
    await tester.enterText(
      find.byKey(XtreamSourceForm.passwordFieldKey),
      'contraseña-real',
    );
  }

  testWidgets('renderiza todos los campos de ui-spec §2.9', (tester) async {
    await pumpSourceForm(tester, const XtreamSourceForm(), overrides: overridesWith());

    expect(find.byKey(XtreamSourceForm.nameFieldKey), findsOneWidget);
    expect(find.byKey(XtreamSourceForm.hostFieldKey), findsOneWidget);
    expect(find.byKey(XtreamSourceForm.usernameFieldKey), findsOneWidget);
    expect(find.byKey(XtreamSourceForm.passwordFieldKey), findsOneWidget);
    expect(find.text('Automatic update'), findsOneWidget);
    expect(find.text('Test connection'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('la contraseña empieza oculta y el toggle la muestra/oculta', (tester) async {
    await pumpSourceForm(tester, const XtreamSourceForm(), overrides: overridesWith());

    Finder passwordTextField() => find.descendant(
      of: find.byKey(XtreamSourceForm.passwordFieldKey),
      matching: find.byType(TextField),
    );

    expect(tester.widget<TextField>(passwordTextField()).obscureText, isTrue);

    await tester.tap(find.byKey(XtreamSourceForm.togglePasswordVisibilityKey));
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(passwordTextField()).obscureText, isFalse);
  });

  group('validación — nombre vacío', () {
    testWidgets('en: muestra el error i18n en inglés', (tester) async {
      await pumpSourceForm(tester, const XtreamSourceForm(), overrides: overridesWith());
      await tester.enterText(find.byKey(XtreamSourceForm.hostFieldKey), 'panel:8080');
      await tester.enterText(find.byKey(XtreamSourceForm.usernameFieldKey), 'demo');
      await tester.enterText(find.byKey(XtreamSourceForm.passwordFieldKey), 'x');

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(fieldError('Enter a name'), findsOneWidget);
    });

    testWidgets('es: muestra el error i18n en español', (tester) async {
      await pumpSourceForm(
        tester,
        const XtreamSourceForm(),
        locale: const Locale('es'),
        overrides: overridesWith(),
      );
      await tester.enterText(find.byKey(XtreamSourceForm.hostFieldKey), 'panel:8080');
      await tester.enterText(find.byKey(XtreamSourceForm.usernameFieldKey), 'demo');
      await tester.enterText(find.byKey(XtreamSourceForm.passwordFieldKey), 'x');

      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(fieldError('Introduce un nombre'), findsOneWidget);
    });
  });

  testWidgets('validación — host vacío: error i18n', (tester) async {
    await pumpSourceForm(tester, const XtreamSourceForm(), overrides: overridesWith());
    await tester.enterText(find.byKey(XtreamSourceForm.nameFieldKey), 'Mi panel');
    await tester.enterText(find.byKey(XtreamSourceForm.usernameFieldKey), 'demo');
    await tester.enterText(find.byKey(XtreamSourceForm.passwordFieldKey), 'x');

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(fieldError('Enter the server URL'), findsOneWidget);
  });

  testWidgets('validación — host malformado: error i18n', (tester) async {
    await pumpSourceForm(tester, const XtreamSourceForm(), overrides: overridesWith());
    await tester.enterText(find.byKey(XtreamSourceForm.nameFieldKey), 'Mi panel');
    await tester.enterText(find.byKey(XtreamSourceForm.hostFieldKey), 'ftp://panel');
    await tester.enterText(find.byKey(XtreamSourceForm.usernameFieldKey), 'demo');
    await tester.enterText(find.byKey(XtreamSourceForm.passwordFieldKey), 'x');

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(fieldError('Enter a valid http(s) host, e.g. host:port'), findsOneWidget);
  });

  testWidgets(
    'validación — credenciales embebidas en el host (ADR-006/P5): error i18n dedicado',
    (tester) async {
      await pumpSourceForm(tester, const XtreamSourceForm(), overrides: overridesWith());
      await tester.enterText(find.byKey(XtreamSourceForm.nameFieldKey), 'Mi panel');
      await tester.enterText(
        find.byKey(XtreamSourceForm.hostFieldKey),
        'http://user:pass@panel:8080',
      );
      await tester.enterText(find.byKey(XtreamSourceForm.usernameFieldKey), 'demo');
      await tester.enterText(find.byKey(XtreamSourceForm.passwordFieldKey), 'x');

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(
        fieldError("Don't include the username or password in the URL — use the fields below"),
        findsOneWidget,
      );
    },
  );

  testWidgets('validación — usuario vacío: error i18n', (tester) async {
    await pumpSourceForm(tester, const XtreamSourceForm(), overrides: overridesWith());
    await tester.enterText(find.byKey(XtreamSourceForm.nameFieldKey), 'Mi panel');
    await tester.enterText(find.byKey(XtreamSourceForm.hostFieldKey), 'panel:8080');
    await tester.enterText(find.byKey(XtreamSourceForm.passwordFieldKey), 'x');

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(fieldError('Enter the username'), findsOneWidget);
  });

  testWidgets('validación — contraseña vacía: error i18n', (tester) async {
    await pumpSourceForm(tester, const XtreamSourceForm(), overrides: overridesWith());
    await tester.enterText(find.byKey(XtreamSourceForm.nameFieldKey), 'Mi panel');
    await tester.enterText(find.byKey(XtreamSourceForm.hostFieldKey), 'panel:8080');
    await tester.enterText(find.byKey(XtreamSourceForm.usernameFieldKey), 'demo');

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(fieldError('Enter the password'), findsOneWidget);
  });

  group('Probar conexión', () {
    testWidgets('éxito: muestra estado, caducidad y nº de streams', (tester) async {
      await pumpSourceForm(
        tester,
        const XtreamSourceForm(),
        overrides: overridesWith(
          probeResult: ProbeOk(
            XtreamProbeSummary(
              account: XtreamAccount(
                username: 'demo',
                status: 'Active',
                isTrial: false,
                activeConnections: 1,
                maxConnections: 2,
                expiresAt: DateTime.utc(2027, 1, 15),
              ),
              liveStreamCount: 42,
            ),
          ),
        ),
      );
      await fillRequiredFields(tester);

      await tester.tap(find.text('Test connection'));
      await tester.pumpAndSettle();

      expect(find.text('Status: Active'), findsOneWidget);
      expect(find.textContaining('Expires'), findsOneWidget);
      expect(find.text('42 live channels'), findsOneWidget);
    });

    testWidgets('éxito sin fecha de caducidad: muestra el texto "sin caducidad"', (
      tester,
    ) async {
      await pumpSourceForm(
        tester,
        const XtreamSourceForm(),
        overrides: overridesWith(
          probeResult: const ProbeOk(
            XtreamProbeSummary(
              account: XtreamAccount(
                username: 'demo',
                status: 'Active',
                isTrial: true,
                activeConnections: 0,
                maxConnections: 1,
              ),
              liveStreamCount: 5,
            ),
          ),
        ),
      );
      await fillRequiredFields(tester);

      await tester.tap(find.text('Test connection'));
      await tester.pumpAndSettle();

      expect(find.text('No expiration date'), findsOneWidget);
    });

    testWidgets(
      'éxito con recuento de streams no disponible: muestra el texto best-effort',
      (tester) async {
        await pumpSourceForm(
          tester,
          const XtreamSourceForm(),
          overrides: overridesWith(
            probeResult: const ProbeOk(
              XtreamProbeSummary(
                account: XtreamAccount(
                  username: 'demo',
                  status: 'Active',
                  isTrial: false,
                  activeConnections: 1,
                  maxConnections: 2,
                ),
              ),
            ),
          ),
        );
        await fillRequiredFields(tester);

        await tester.tap(find.text('Test connection'));
        await tester.pumpAndSettle();

        expect(find.text('Live channel count unavailable'), findsOneWidget);
      },
    );

    testWidgets('fallo (auth): muestra el mensaje i18n del motivo', (tester) async {
      await pumpSourceForm(
        tester,
        const XtreamSourceForm(),
        overrides: overridesWith(
          probeResult: const ProbeFailed(ProbeFailureReason.authFailed),
        ),
      );
      await fillRequiredFields(tester);

      await tester.tap(find.text('Test connection'));
      await tester.pumpAndSettle();

      expect(find.text('Incorrect username or password.'), findsOneWidget);
    });

    testWidgets('no dispara la petición si el host tiene credenciales embebidas', (
      tester,
    ) async {
      final probe = FakeXtreamProbe(
        const ProbeOk(
          XtreamProbeSummary(
            account: XtreamAccount(
              username: 'demo',
              status: 'Active',
              isTrial: false,
              activeConnections: 0,
              maxConnections: 1,
            ),
          ),
        ),
      );
      await pumpSourceForm(
        tester,
        const XtreamSourceForm(),
        overrides: [
          ...overridesWith(),
          xtreamProbeProvider.overrideWithValue(probe),
        ],
      );
      await tester.enterText(find.byKey(XtreamSourceForm.nameFieldKey), 'Mi panel');
      await tester.enterText(
        find.byKey(XtreamSourceForm.hostFieldKey),
        'http://user:pass@panel:8080',
      );
      await tester.enterText(find.byKey(XtreamSourceForm.usernameFieldKey), 'demo');
      await tester.enterText(find.byKey(XtreamSourceForm.passwordFieldKey), 'x');

      await tester.tap(find.text('Test connection'));
      await tester.pumpAndSettle();

      expect(probe.lastHost, isNull);
      expect(
        fieldError("Don't include the username or password in the URL — use the fields below"),
        findsOneWidget,
      );
    });
  });

  group('Guardar', () {
    testWidgets(
      'envío correcto: llama a SaveSource con el XtreamSourceConfig exacto, hace pop y muestra snackbar',
      (tester) async {
        await pumpSourceForm(tester, const XtreamSourceForm(), overrides: overridesWith());
        await fillRequiredFields(tester, name: 'Mi panel');

        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        expect(sources.savedSources, hasLength(1));
        final saved = sources.savedSources.single;
        expect(saved.name, 'Mi panel');
        expect(saved.lastRefresh, isNull);
        final config = saved.config as XtreamSourceConfig;
        expect(config.host, Uri.parse('http://panel.example:8080'));
        expect(config.username, 'demo');

        expect(find.byKey(XtreamSourceForm.nameFieldKey), findsNothing);
        expect(find.byKey(openButtonKey), findsOneWidget);
        expect(find.text('Source "Mi panel" saved'), findsOneWidget);
      },
    );

    testWidgets('nombre duplicado: muestra el error i18n y no navega atrás', (tester) async {
      await sources.upsert(
        Source(
          id: 'existente',
          config: XtreamSourceConfig(
            host: Uri.parse('http://otro-panel:8080'),
            username: 'otro',
          ),
          name: 'Mi panel',
          updatedAt: DateTime.utc(2026, 8, 1),
        ),
      );
      await pumpSourceForm(tester, const XtreamSourceForm(), overrides: overridesWith());
      await fillRequiredFields(tester, name: 'Mi panel');

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('A source with this name already exists'), findsOneWidget);
      expect(find.byKey(XtreamSourceForm.nameFieldKey), findsOneWidget);
    });
  });

  group('P5 — anti-fuga de credenciales', () {
    testWidgets('la contraseña guardada en el almacén seguro coincide, y nunca aparece en pantalla', (
      tester,
    ) async {
      await pumpSourceForm(tester, const XtreamSourceForm(), overrides: overridesWith());
      await fillRequiredFields(tester, name: 'Mi panel');

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(secureStore.secrets['xtream-1'], 'contraseña-real');
      expect(find.text('contraseña-real'), findsNothing);
    });

    testWidgets('la contraseña nunca entra en el Source persistido (toString no la contiene)', (
      tester,
    ) async {
      await pumpSourceForm(tester, const XtreamSourceForm(), overrides: overridesWith());
      await fillRequiredFields(tester, name: 'Mi panel');

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final saved = sources.savedSources.single;
      expect(saved.toString(), isNot(contains('contraseña-real')));
      expect(saved.config.toString(), isNot(contains('contraseña-real')));
    });

    testWidgets('un fallo del probe no expone la contraseña en el banner de error', (
      tester,
    ) async {
      await pumpSourceForm(
        tester,
        const XtreamSourceForm(),
        overrides: overridesWith(
          probeResult: const ProbeFailed(ProbeFailureReason.authFailed),
        ),
      );
      await fillRequiredFields(tester, name: 'Mi panel');

      await tester.tap(find.text('Test connection'));
      await tester.pumpAndSettle();

      // La contraseña sigue en su propio campo (es el valor que el usuario
      // tecleó ahí) — lo que este test comprueba es que NO aparece además
      // en el banner de error, es decir, ninguna ocurrencia fuera de ese
      // campo de contraseña.
      final occurrencesOutsidePasswordField = find.text('contraseña-real').evaluate().where(
        (element) =>
            find
                .ancestor(
                  of: find.byWidget(element.widget),
                  matching: find.byKey(XtreamSourceForm.passwordFieldKey),
                )
                .evaluate()
                .isEmpty,
      );
      expect(occurrencesOutsidePasswordField, isEmpty);
    });

    testWidgets('si el upsert falla tras guardar el secreto, SaveSource lo borra (sin huérfanos)', (
      tester,
    ) async {
      sources.failUpsert = true;
      await pumpSourceForm(tester, const XtreamSourceForm(), overrides: overridesWith());
      await fillRequiredFields(tester, name: 'Mi panel');

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(secureStore.secrets, isEmpty);
      expect(find.text("Couldn't save the source. Try again."), findsOneWidget);
    });
  });
}
