import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/l10n/app_localizations.dart';

/// Harness compartido entre `m3u_source_form_test.dart` y
/// `xtream_source_form_test.dart` (S4 · Ola 2). Empuja [form] como una
/// ruta real (no lo pone directo en `home`): así `Navigator.pop()` dentro
/// del formulario es observable — tras un guardado con éxito, el botón
/// `_openButtonKey` vuelve a ser el único visible.
///
/// `wrap()` de `desktop_shell_test.dart` es el precedente de esta
/// configuración de `MaterialApp` (delegates + `supportedLocales`); este
/// harness añade el `Navigator` real que los formularios necesitan.
final openButtonKey = UniqueKey();

Future<void> pumpSourceForm(
  WidgetTester tester,
  Widget form, {
  Locale locale = const Locale('en'),
  List<Override> overrides = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                key: openButtonKey,
                onPressed: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute<void>(builder: (_) => form)),
                child: const Text('open form'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(openButtonKey));
  await tester.pumpAndSettle();
}

/// Cierra el `Finder` sobre el mensaje de error de un `TextFormField`
/// (Flutter renderiza el texto de `validator` como un `Text` descendiente
/// del propio campo — buscarlo sin acotar podría chocar con un `Text` de
/// etiqueta con el mismo contenido en otro campo).
Finder fieldError(String message) => find.text(message);
