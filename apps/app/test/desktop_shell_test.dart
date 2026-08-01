import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/l10n/app_localizations.dart';
import 'package:iptv_app/shell/desktop_shell.dart';

/// DesktopShell navegable (S4 · Desktop I, Ola 1). Escrito ANTES de la
/// implementación real del NavigationRail (deben fallar en rojo hasta esa
/// implementación); ver ui-spec.md §1 para los 9 destinos y el "Hecho
/// cuando" de la tarea de Notion.
void main() {
  Widget wrap(Widget child, {Locale locale = const Locale('en')}) {
    return ProviderScope(
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    );
  }

  // Los finders de etiqueta se acotan al NavigationRail: la sección activa
  // (IndexedStack) muestra un placeholder con el mismo texto que su propio
  // destino de navegación, así que `find.text(label)` sin acotar encuentra
  // dos coincidencias para la sección seleccionada.
  Finder railLabel(String label) => find.descendant(
    of: find.byType(NavigationRail),
    matching: find.text(label),
  );

  testWidgets('renderiza con los 9 destinos visibles en el rail', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const DesktopShell()));
    await tester.pumpAndSettle();

    for (final label in const [
      'Home',
      'Live TV',
      'Movies',
      'Series',
      'Search',
      'Guide',
      'Favorites',
      'Sources',
      'Settings',
    ]) {
      expect(railLabel(label), findsOneWidget);
    }
  });

  testWidgets('tocar un destino cambia la sección activa del IndexedStack', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const DesktopShell()));
    await tester.pumpAndSettle();

    final stackBefore = tester.widget<IndexedStack>(find.byType(IndexedStack));
    expect(stackBefore.index, 0);

    await tester.tap(railLabel('Sources'));
    await tester.pumpAndSettle();

    final stackAfter = tester.widget<IndexedStack>(find.byType(IndexedStack));
    expect(stackAfter.index, isNot(0));
  });

  testWidgets('todas las etiquetas vienen de AppLocalizations (es vs en)', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(const DesktopShell(), locale: const Locale('es')),
    );
    await tester.pumpAndSettle();

    for (final label in const [
      'Inicio',
      'TV en directo',
      'Películas',
      'Series',
      'Buscar',
      'Guía',
      'Favoritos',
      'Fuentes',
      'Ajustes',
    ]) {
      expect(railLabel(label), findsOneWidget);
    }
    expect(railLabel('Home'), findsNothing);
    expect(railLabel('Sources'), findsNothing);
  });

  testWidgets('Ctrl+2 activa la segunda sección', (tester) async {
    await tester.pumpWidget(wrap(const DesktopShell()));
    await tester.pumpAndSettle();
    // El propio DesktopShell debe tener el foco para recibir el atajo.
    await tester.tap(find.byType(DesktopShell));
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pumpAndSettle();

    final stack = tester.widget<IndexedStack>(find.byType(IndexedStack));
    expect(stack.index, 1);
  });
}
