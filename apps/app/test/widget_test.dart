import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/features/sources/source_providers.dart';
import 'package:iptv_app/main.dart';

import 'features/sources/_helpers/fakes.dart';

void main() {
  testWidgets('la app arranca y muestra un shell', (tester) async {
    // La sección Fuentes (S4 · Ola 3) está cableada a persistencia real —
    // sin este override, el smoke test intenta abrir una BD real y
    // pumpAndSettle() nunca termina (ver desktop_shell_test.dart).
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sourceRepositoryProvider.overrideWithValue(FakeSourceRepository()),
        ],
        child: const IptvApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
