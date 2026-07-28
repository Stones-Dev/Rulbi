import 'dart:convert';

import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_pairing/iptv_pairing.dart';
import 'package:test/test.dart';

void main() {
  ConfigPackage samplePackage() {
    const channel = ChannelRef(sourceId: 's1', key: 'canal-1');
    return ConfigPackage(
      sources: [
        SourceExport(
          source: Source(
            id: 's1',
            name: 'Mi panel',
            config: XtreamSourceConfig(
              host: Uri.parse('http://panel.example.com:8080'),
              username: 'usuario',
            ),
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
          secret: 'contraseña-super-secreta',
        ),
      ],
      favorites: [
        Favorite(channel: channel, order: 0, updatedAt: DateTime.utc(2026, 1, 2)),
      ],
      watchState: [
        WatchState(
          channel: channel,
          position: const Duration(minutes: 12),
          duration: const Duration(minutes: 45),
          updatedAt: DateTime.utc(2026, 1, 3),
        ),
      ],
      settings: const {'theme': 'dark'},
    );
  }

  group('round-trip', () {
    test('el canal cifrado conserva sources, favoritos, watch-state y secretos', () {
      final original = samplePackage();
      final wire = jsonEncode(original.toJsonForSecureChannel());
      final decoded = ConfigPackage.fromJson(
        jsonDecode(wire) as Map<String, Object?>,
      );

      expect(decoded.sources, hasLength(1));
      expect(decoded.sources.single.source, original.sources.single.source);
      expect(decoded.sources.single.secret, 'contraseña-super-secreta');
      expect(decoded.favorites, original.favorites);
      expect(decoded.watchState, original.watchState);
      expect(decoded.settings, original.settings);
    });

    test(
      'la exportación a archivo nunca serializa el secreto, ni siquiera dentro del JSON',
      () {
        final original = samplePackage();
        final wire = jsonEncode(original.toJsonForFileExport());

        expect(wire, isNot(contains('contraseña-super-secreta')));

        final decoded = ConfigPackage.fromJson(
          jsonDecode(wire) as Map<String, Object?>,
        );
        expect(decoded.sources.single.secret, isNull);
      },
    );
  });

  group('tolerancia de versión', () {
    test('ignora campos desconocidos de una versión igual o anterior', () {
      final json = samplePackage().toJsonForSecureChannel();
      json['un_campo_del_futuro_que_no_conocemos'] = {'x': 1};
      (json['sources'] as List).cast<Map<String, Object?>>().first['otro_campo_futuro'] = 42;

      expect(() => ConfigPackage.fromJson(json), returnsNormally);
    });

    test('rechaza con un error claro una versión mayor que la soportada', () {
      final json = samplePackage().toJsonForSecureChannel();
      json['v'] = ConfigPackage.currentVersion + 1;

      expect(
        () => ConfigPackage.fromJson(json),
        throwsA(isA<UnsupportedConfigVersionException>()),
      );
    });
  });

  test('un paquete vacío no revienta al reconstruirse', () {
    final decoded = ConfigPackage.fromJson(const {'v': 1});
    expect(decoded.sources, isEmpty);
    expect(decoded.favorites, isEmpty);
    expect(decoded.watchState, isEmpty);
    expect(decoded.settings, isEmpty);
  });
}
