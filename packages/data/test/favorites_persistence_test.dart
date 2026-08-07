import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_data/iptv_data.dart';

/// Persistencia de favoritos tras un reinicio simulado (S5 · Ola 2, mismo
/// patrón de fichero real que `import_differential_test.dart`): favoritos
/// y su orden manual deben sobrevivir a cerrar y reabrir la BD, no solo a
/// vivir en la misma conexión abierta durante el test.
void main() {
  test(
    'marcar, reordenar y reabrir la BD desde el mismo fichero conserva '
    'favoritos y sortOrder',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'iptv_favorites_persistence_test_',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) await tempDir.delete(recursive: true);
      });
      final file = File('${tempDir.path}/favorites.sqlite');

      const a = ChannelRef(sourceId: 's1', key: 'a');
      const b = ChannelRef(sourceId: 's1', key: 'b');
      const c = ChannelRef(sourceId: 's1', key: 'c');

      final firstOpen = IptvDatabase(NativeDatabase(file));
      final firstRepository = DriftFavoritesRepository(firstOpen);
      for (final (ref, order) in [(a, 0), (b, 1), (c, 2)]) {
        await firstRepository.upsert(
          Favorite(channel: ref, order: order, updatedAt: DateTime(2026, 1, 1)),
        );
      }
      await ManageFavorites(
        firstRepository,
        const SystemClock(),
      ).reorder([c, a, b]);
      await firstOpen.close();

      // Reabre el MISMO fichero — nada de estado en memoria compartido con
      // la conexión anterior, exactamente como reabrir la app.
      final secondOpen = IptvDatabase(NativeDatabase(file));
      addTearDown(secondOpen.close);
      final secondRepository = DriftFavoritesRepository(secondOpen);

      final all = await secondRepository.getAll();
      expect(all.map((f) => f.channel), [c, a, b]);
      expect(all.map((f) => f.order), [0, 1, 2]);
      expect(all.every((f) => !f.isDeleted), isTrue);
    },
  );

  test('un favorito desmarcado (tombstone) sigue tumbado tras reabrir', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'iptv_favorites_persistence_test_',
    );
    addTearDown(() async {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });
    final file = File('${tempDir.path}/favorites.sqlite');
    const channel = ChannelRef(sourceId: 's1', key: 'a');

    final firstOpen = IptvDatabase(NativeDatabase(file));
    final firstRepository = DriftFavoritesRepository(firstOpen);
    final manageFavorites = ManageFavorites(firstRepository, const SystemClock());
    await manageFavorites.toggle(channel); // marca
    await manageFavorites.toggle(channel); // desmarca (tombstone)
    await firstOpen.close();

    final secondOpen = IptvDatabase(NativeDatabase(file));
    addTearDown(secondOpen.close);
    final found = await DriftFavoritesRepository(secondOpen).find(channel);
    expect(found, isNotNull);
    expect(found!.isDeleted, isTrue);
  });
}
