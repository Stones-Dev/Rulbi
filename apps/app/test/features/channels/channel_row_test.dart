import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/features/channels/channel_row.dart';
import 'package:iptv_app/features/epg/epg_providers.dart';
import 'package:iptv_app/features/sources/source_providers.dart';
import 'package:iptv_app/l10n/app_localizations.dart';
import 'package:iptv_core/iptv_core.dart';

import '../../_helpers/fake_epg_repository.dart';
import '../../_helpers/fake_favorites_repository.dart';

/// `ChannelRow` — badge de favorito (ui-spec §2.3) y subtítulo/barra EPG
/// (S5 · Ola 2, ADR-008). `EpgProgressBar` se prueba aquí a través de
/// `ChannelRow`, no aislado: es como se usa de verdad.
void main() {
  final channel = Channel(
    ref: const ChannelRef(sourceId: 's1', key: 'canal-1'),
    sourceId: 's1',
    type: ContentType.live,
    name: 'Canal Uno',
    url: Uri.parse('http://example.com/canal-1'),
    tvgId: 'tvg-1',
  );

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    required List<Override> overrides,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: child),
        ),
      ),
    );
    // `favoriteRefsProvider` es un `StreamProvider`: su primer valor llega
    // por un `async*` (aunque el primer `yield` sea síncrono en el
    // `Stream`, entregarlo al widget cuesta un turno de microtask/frame
    // real) — sin este segundo pump, el badge se pinta con el estado
    // "cargando" inicial en vez del valor sembrado.
    await tester.pump();
  }

  group('badge de favorito', () {
    testWidgets('canal sin favorito muestra el icono vacío', (tester) async {
      await pump(
        tester,
        ChannelRow(channel: channel),
        overrides: [
          favoritesRepositoryProvider.overrideWithValue(FakeFavoritesRepository()),
        ],
      );

      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
      expect(find.byIcon(Icons.favorite), findsNothing);
    });

    testWidgets(
      'tocar el badge marca como favorito y el icono cambia',
      (tester) async {
        final favorites = FakeFavoritesRepository();
        await pump(
          tester,
          ChannelRow(channel: channel),
          overrides: [
            favoritesRepositoryProvider.overrideWithValue(favorites),
          ],
        );

        await tester.tap(
          find.byKey(Key('channelRow.favorite.${channel.ref.serialized}')),
        );
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.favorite), findsOneWidget);
        expect(find.byIcon(Icons.favorite_border), findsNothing);
        final saved = await favorites.find(channel.ref);
        expect(saved, isNotNull);
        expect(saved!.isDeleted, isFalse);
      },
    );

    testWidgets(
      'tocar el badge de un favorito existente lo desmarca (tombstone)',
      (tester) async {
        final favorites = FakeFavoritesRepository()
          ..seed(Favorite(channel: channel.ref, updatedAt: DateTime.utc(2026, 1, 1)));
        await pump(
          tester,
          ChannelRow(channel: channel),
          overrides: [
            favoritesRepositoryProvider.overrideWithValue(favorites),
          ],
        );
        expect(find.byIcon(Icons.favorite), findsOneWidget);

        await tester.tap(
          find.byKey(Key('channelRow.favorite.${channel.ref.serialized}')),
        );
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.favorite_border), findsOneWidget);
        final saved = await favorites.find(channel.ref);
        expect(saved!.isDeleted, isTrue);
      },
    );
  });

  group('subtítulo/barra EPG', () {
    testWidgets('sin epgController: ni subtítulo ni barra', (tester) async {
      await pump(
        tester,
        ChannelRow(channel: channel),
        overrides: [
          favoritesRepositoryProvider.overrideWithValue(FakeFavoritesRepository()),
        ],
      );

      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets(
      'canal sin guía (con epgController, sin datos): ni subtítulo ni barra '
      '— estado vacío explícito, RNF-09',
      (tester) async {
        final controller = EpgNowController(repository: FakeEpgRepository());

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              favoritesRepositoryProvider.overrideWithValue(FakeFavoritesRepository()),
              epgRepositoryProvider.overrideWithValue(FakeEpgRepository()),
            ],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: ChannelRow(channel: channel, epgController: controller),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(LinearProgressIndicator), findsNothing);
      },
    );

    testWidgets(
      'canal con programa activo: título y barra con la fracción esperada',
      (tester) async {
        final now = DateTime.utc(2026, 8, 6, 12);
        final epgRepository = FakeEpgRepository()
          ..seed(
            EpgProgramme(
              tvgId: 'tvg-1',
              start: now.subtract(const Duration(minutes: 15)),
              stop: now.add(const Duration(minutes: 45)),
              title: 'El Informativo',
            ),
          );

        final controller = EpgNowController(repository: epgRepository);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              favoritesRepositoryProvider.overrideWithValue(FakeFavoritesRepository()),
              epgRepositoryProvider.overrideWithValue(epgRepository),
              // `epgClockProvider` por defecto usa `DateTime.now()` real —
              // sin fijarlo, la consulta iría por la hora real de cuando
              // corre el test, no por el `now` fijo con el que se sembró
              // el programa.
              epgClockProvider.overrideWithValue(ValueNotifier<DateTime>(now)),
            ],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: ChannelRow(channel: channel, epgController: controller),
              ),
            ),
          ),
        );
        // `pumpAndSettle` (no un par de `pump()` fijo): además del stream
        // de favoritos, `request()` dispara `_flush` en un microtask que
        // a su vez llama a `notifyListeners()` — con el bucle de
        // `request()`/`invalidateIfStale` ya corregido, esto converge
        // solo, sin quedarse pendiente.
        await tester.pumpAndSettle();

        expect(find.text('El Informativo'), findsOneWidget);
        final bar = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        );
        // 15 min transcurridos de 60 totales -> 0.25.
        expect(bar.value, closeTo(0.25, 0.001));
      },
    );

    testWidgets(
      'cuando el programa "ahora" termina, un tick del reloj recarga '
      'contra la BD en vez de seguir mostrando el programa ya terminado',
      (tester) async {
        final start = DateTime.utc(2026, 8, 6, 12);
        final clock = ValueNotifier<DateTime>(start);
        final epgRepository = FakeEpgRepository()
          ..seed(
            EpgProgramme(
              tvgId: 'tvg-1',
              start: start,
              stop: start.add(const Duration(minutes: 30)),
              title: 'Termina pronto',
            ),
          );
        final controller = EpgNowController(repository: epgRepository);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              favoritesRepositoryProvider.overrideWithValue(FakeFavoritesRepository()),
              epgRepositoryProvider.overrideWithValue(epgRepository),
              epgClockProvider.overrideWithValue(clock),
            ],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: ChannelRow(channel: channel, epgController: controller),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Termina pronto'), findsOneWidget);

        // El reloj avanza más allá de `stop` — mismo tick de 30 s que usa
        // `epgClockProvider` en producción, aquí forzado a mano.
        clock.value = start.add(const Duration(minutes: 30));
        await tester.pumpAndSettle();

        // El repositorio no tiene nada más para ese instante (sin
        // "siguiente" sembrado) — el estado correcto es "sin EPG ahora",
        // nunca seguir mostrando el programa que ya terminó.
        expect(find.text('Termina pronto'), findsNothing);
        expect(find.byType(LinearProgressIndicator), findsNothing);
      },
    );
  });
}
