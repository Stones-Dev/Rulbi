import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/widgets/media_card.dart';
import 'package:iptv_tokens/iptv_tokens.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    theme: IptvTheme.dark(),
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets('sin imageUrl, muestra el fallback con el icono y el label', (tester) async {
    await tester.pumpWidget(
      wrap(const MediaCard(imageUrl: null, fallbackLabel: 'El Faro Rojo', title: 'El Faro Rojo')),
    );

    expect(find.byIcon(Symbols.movie_rounded), findsOneWidget);
    expect(find.text('El Faro Rojo'), findsOneWidget);
  });

  testWidgets('sin title ni footer, no pinta el degradado inferior', (tester) async {
    await tester.pumpWidget(wrap(const MediaCard(imageUrl: null, fallbackLabel: 'Umbra')));

    expect(find.text('Umbra'), findsNothing);
  });

  testWidgets('con progress, pinta LinearProgressIndicator con el valor exacto', (tester) async {
    await tester.pumpWidget(
      wrap(const MediaCard(imageUrl: null, fallbackLabel: 'El Faro Rojo', title: 'El Faro Rojo', progress: 0.42)),
    );

    final indicator = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(indicator.value, 0.42);
  });

  testWidgets('sin progress, no pinta LinearProgressIndicator', (tester) async {
    await tester.pumpWidget(wrap(const MediaCard(imageUrl: null, fallbackLabel: 'El Faro Rojo', title: 'El Faro Rojo')));

    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('badge se pinta cuando se pasa uno', (tester) async {
    await tester.pumpWidget(
      wrap(
        const MediaCard(
          imageUrl: null,
          fallbackLabel: 'Canal 5',
          badge: Text('EN DIRECTO', key: Key('liveBadge')),
        ),
      ),
    );

    expect(find.byKey(const Key('liveBadge')), findsOneWidget);
  });

  testWidgets('footer arbitrario (p. ej. un widget reactivo tipo EpgProgressBar) se pinta bajo el título', (tester) async {
    await tester.pumpWidget(
      wrap(
        const MediaCard(
          imageUrl: null,
          fallbackLabel: 'Canal 5',
          title: 'Canal 5',
          footer: Text('Programa actual', key: Key('footer')),
        ),
      ),
    );

    expect(find.byKey(const Key('footer')), findsOneWidget);
  });

  testWidgets('onTap se dispara al tocar la tarjeta, con la itemKey esperada', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      wrap(
        MediaCard(
          itemKey: const Key('continueWatching.ref-1'),
          imageUrl: null,
          fallbackLabel: 'El Faro Rojo',
          onTap: () => tapped = true,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('continueWatching.ref-1')));
    expect(tapped, isTrue);
  });

  testWidgets('al recibir foco, muestra el anillo blanco + halo (IptvFocus, ui-spec §5.3)', (tester) async {
    await tester.pumpWidget(
      wrap(MediaCard(itemKey: const Key('mediaCard.test'), imageUrl: null, fallbackLabel: 'El Faro Rojo', onTap: () {})),
    );

    final cardFinder = find.byKey(const Key('mediaCard.test'));
    // Mismo patrón que channel_list_screen_test.dart: el ancestro `Focus`
    // más cercano al `InkWell` de la tarjeta, `.first` porque hay otros
    // `Focus` más arriba en el árbol (Scaffold/MaterialApp).
    final focusWidget = tester
        .widgetList<Focus>(find.ancestor(of: cardFinder, matching: find.byType(Focus)))
        .first;

    focusWidget.focusNode!.requestFocus();
    await tester.pump();
    await tester.pump();

    final container = tester.widget<Container>(cardFinder);
    final decoration = container.decoration as BoxDecoration?;
    expect(decoration?.border, isNotNull);
    expect(decoration?.boxShadow, isNotNull);
  });

  testWidgets('tamaño fijo 220x124, el del frame canónico 38:3', (tester) async {
    await tester.pumpWidget(wrap(const MediaCard(imageUrl: null, fallbackLabel: 'El Faro Rojo')));

    final size = tester.getSize(find.byType(MediaCard));
    expect(size.width, MediaCard.width);
    expect(size.height, MediaCard.height);
  });
}
