import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/main.dart';

void main() {
  testWidgets('la app arranca y muestra un shell', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: IptvApp()));
    await tester.pumpAndSettle();

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
