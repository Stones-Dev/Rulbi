import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/shell/tv_focusable.dart';
import 'package:iptv_tokens/iptv_tokens.dart';

void main() {
  testWidgets('TvFocusable renderiza el hijo y no muestra anillo sin foco', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TvFocusable(
            child: Text('TV Card Content'),
          ),
        ),
      ),
    );

    expect(find.text('TV Card Content'), findsOneWidget);

    final container = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    final decoration = container.decoration as BoxDecoration?;
    expect(decoration?.border, isNull);
    expect(decoration?.boxShadow, isNull);
  });

  testWidgets('TvFocusable muestra anillo y halo al obtener foco', (
    tester,
  ) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvFocusable(
            focusNode: focusNode,
            child: const Text('TV Card Content'),
          ),
        ),
      ),
    );

    focusNode.requestFocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    final container = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    final decoration = container.decoration as BoxDecoration?;
    expect(decoration?.border, isNotNull);
    expect(decoration?.border?.top.color, IptvFocus.ringColor);
    expect(decoration?.boxShadow, isNotNull);
    expect(decoration?.boxShadow?.first.color, IptvFocus.haloColor);
  });

  testWidgets('TvFocusable ejecuta onTap al pulsar D-pad Center o Enter', (
    tester,
  ) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    var tapCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvFocusable(
            focusNode: focusNode,
            onTap: () => tapCount++,
            child: const Text('Clickable'),
          ),
        ),
      ),
    );

    focusNode.requestFocus();
    await tester.pump();

    // Evento LogicalKeyboardKey.select (D-pad Center)
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(tapCount, 1);

    // Evento LogicalKeyboardKey.enter
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(tapCount, 2);
  });
}
