import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/features/settings/settings_screen.dart';
import 'package:iptv_app/features/sources/source_providers.dart';
import 'package:iptv_app/l10n/app_localizations.dart';

import '../../_helpers/fake_epg_repository.dart';
import '../../_helpers/fake_favorites_repository.dart';
import '../channels/_helpers/fake_channel_repository.dart';
import '../sources/_helpers/fakes.dart';

/// Regresión del bug de verificación E2E de S7 (Antigravity, emulador
/// Android): `MobileShell`/`SettingsScreen` empujaban `SourcesScreen` y
/// `FavoritesScreen` directas con `MaterialPageRoute`, y ninguna de las dos
/// trae `Scaffold`/`Material` propio (están pensadas para vivir embebidas
/// en `DesktopShell`) — "No Material widget found" en cuanto la ruta
/// renderiza un `ListTile`/`Chip`/`Switch`.
///
/// A diferencia de `sources_screen_test.dart` (que inyecta el `Scaffold`
/// que faltaba en producción: `home: const Scaffold(body: SourcesScreen())`)
/// y de `mobile_shell_test.dart` (que abre Ajustes pero nunca pulsa un
/// tile), este archivo ejercita la ruta real: `SettingsScreen` sin
/// `Scaffold` de test alrededor, pulsando cada tile.
void main() {
  Widget wrap(Widget child) {
    return ProviderScope(
      overrides: [
        sourceRepositoryProvider.overrideWithValue(FakeSourceRepository()),
        secureCredentialStoreProvider.overrideWithValue(
          FakeSecureCredentialStore(),
        ),
        channelRepositoryProvider.overrideWithValue(
          FakeChannelListRepository(),
        ),
        clockProvider.overrideWithValue(FixedClock(DateTime.utc(2026, 8, 6))),
        m3uImportChannelSourceProvider.overrideWithValue(
          FakeImportChannelSource(channels: const Stream.empty()),
        ),
        favoritesRepositoryProvider.overrideWithValue(
          FakeFavoritesRepository(),
        ),
        epgRepositoryProvider.overrideWithValue(FakeEpgRepository()),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    );
  }

  testWidgets(
    'tocar el tile de Fuentes no revienta con "No Material widget found"',
    (tester) async {
      await tester.pumpWidget(wrap(const SettingsScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sources'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // La ruta trae su propio AppBar con el título — antes no había
      // AppBar en absoluto (ni, por tanto, flecha de retroceso).
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('Sources')),
        findsOneWidget,
      );
      expect(find.byType(BackButton), findsOneWidget);
      // El título de sección no debe salir duplicado (AppBar + cabecera
      // interna de SourcesScreen).
      expect(find.text('Sources'), findsOneWidget);
    },
  );

  testWidgets(
    'tocar el tile de Favoritos no revienta con "No Material widget found"',
    (tester) async {
      await tester.pumpWidget(wrap(const SettingsScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Favorites'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Favorites'),
        ),
        findsOneWidget,
      );
      expect(find.byType(BackButton), findsOneWidget);
    },
  );
}
