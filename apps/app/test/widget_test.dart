import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/features/sources/source_providers.dart';
import 'package:iptv_app/main.dart';

import '_helpers/fake_epg_repository.dart';
import '_helpers/fake_favorites_repository.dart';
import 'features/channels/_helpers/fake_channel_repository.dart';
import 'features/home/_helpers/fake_watch_state_repository.dart';
import 'features/sources/_helpers/fakes.dart';

void main() {
  testWidgets('la app arranca y muestra un shell', (tester) async {
    // La sección Fuentes (S4 · Ola 3) y, desde S5 · Ola 1/2, Inicio/TV en
    // directo/Favoritos están cableadas a persistencia real — sin estos
    // overrides, el smoke test intenta abrir una BD real y
    // pumpAndSettle() nunca termina (ver desktop_shell_test.dart).
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sourceRepositoryProvider.overrideWithValue(FakeSourceRepository()),
          channelRepositoryProvider.overrideWithValue(
            FakeChannelListRepository(),
          ),
          watchStateRepositoryProvider.overrideWithValue(
            FakeWatchStateRepository(),
          ),
          favoritesRepositoryProvider.overrideWithValue(
            FakeFavoritesRepository(),
          ),
          epgRepositoryProvider.overrideWithValue(FakeEpgRepository()),
        ],
        child: const IptvApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
