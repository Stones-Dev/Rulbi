import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/features/epg/epg_providers.dart';
import 'package:iptv_app/features/sources/source_providers.dart';
import 'package:iptv_app/main.dart';
import 'package:iptv_core/iptv_core.dart';

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
    //
    // `epgIngestProvider` (S5.5, Bloque B4): `IptvApp.initState` arranca
    // `epgRefreshSchedulerProvider`, que construye la cadena completa de
    // `RunEpgRefresh` en cuanto se lee — incluida `epgIngestProvider`, que
    // sin overridear tira de `xmltvEpgWriterProvider` ->
    // `iptvDatabaseProvider` -> BD real, aunque `FakeSourceRepository()` no
    // tenga ninguna fuente y `ingestFor` nunca llegue a invocarse de
    // verdad. Un fake que nunca hace nada basta: no hay fuentes que
    // refrescar en este smoke test.
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
          epgIngestProvider.overrideWithValue(_NoopEpgIngestPort()),
        ],
        child: const IptvApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}

final class _NoopEpgIngestPort implements EpgIngestPort {
  @override
  Future<EpgImportStats?> ingestFor(Source source, {required DateTime now}) async => null;
}
