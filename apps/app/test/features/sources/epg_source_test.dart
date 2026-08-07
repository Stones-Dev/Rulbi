import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:iptv_app/features/sources/epg_source.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:test/test.dart';

import '_helpers/fakes.dart';

/// `XmltvEpgSource.epgFor` (S5 · Ola 2 ADR-008; S5.5 Bloque A2 añade
/// Xtream vía `xmltv.php`). Sin red real: `epgFor` solo construye el
/// `XmltvParseOutcome` — `parseXmltv` no empieza a consumir bytes hasta
/// que algo escucha `.entries` (ver su docstring), así que comprobar
/// `epgFor(...) != null` sin tocar `.entries` nunca dispara una petición
/// HTTP de verdad. Lo mismo aplica a la credencial Xtream: se lee dentro
/// del generador `async*` de `_fetchUrl`, no en `epgFor` — construir el
/// `XmltvParseOutcome` nunca toca `SecureCredentialStore`.
void main() {
  final now = DateTime.utc(2026, 8, 6);

  Source m3uUrlSource({Uri? epgUrl}) => Source(
    id: 's1',
    config: M3uUrlSourceConfig(
      url: Uri.parse('http://example.com/list.m3u'),
      epgUrl: epgUrl,
    ),
    name: 'Mi lista',
    updatedAt: now,
  );

  Source m3uFileSource({Uri? epgUrl}) => Source(
    id: 's1',
    config: M3uFileSourceConfig(filePath: '/tmp/list.m3u', epgUrl: epgUrl),
    name: 'Mi lista',
    updatedAt: now,
  );

  Source xtreamSource() => Source(
    id: 's1',
    config: XtreamSourceConfig(
      host: Uri.parse('http://panel.example.com'),
      username: 'user',
    ),
    name: 'Mi panel',
    updatedAt: now,
  );

  group('sin epgUrl', () {
    test('M3uUrlSourceConfig sin epgUrl → null', () {
      final source = XmltvEpgSource(secureStore: FakeSecureCredentialStore());
      expect(source.epgFor(m3uUrlSource(), now: now), isNull);
    });

    test('M3uFileSourceConfig sin epgUrl → null', () {
      final source = XmltvEpgSource(secureStore: FakeSecureCredentialStore());
      expect(source.epgFor(m3uFileSource(), now: now), isNull);
    });
  });

  group('Xtream — xmltv.php del panel (S5.5, Bloque A2)', () {
    test('XtreamSourceConfig → no-null, sin necesitar la credencial todavía', () {
      // No hace falta que la credencial exista en el store para que
      // epgFor construya el outcome: solo se lee al consumir `.entries`
      // (ver docstring de arriba y el grupo de abajo).
      final source = XmltvEpgSource(secureStore: FakeSecureCredentialStore());
      expect(source.epgFor(xtreamSource(), now: now), isNotNull);
    });

    test('sin credencial guardada, .entries falla explícitamente y nunca pide xmltv.php', () async {
      final store = FakeSecureCredentialStore();
      final calls = <Uri>[];
      final client = MockClient((request) async {
        calls.add(request.url);
        return http.Response('', 200);
      });
      final source = XmltvEpgSource(secureStore: store, client: client);

      final outcome = source.epgFor(xtreamSource(), now: now)!;
      // Mismo motivo que `_runEpgPhase` (import_controller.dart): si
      // `entries` falla, `report` completa con el mismo error y nunca se
      // llega a `await`lo — sin `.ignore()`, Dart lo reporta como
      // excepción sin manejar aunque el catch de abajo ya la está
      // tratando.
      outcome.report.ignore();

      await expectLater(outcome.entries.drain<void>(), throwsA(anything));
      expect(calls, isEmpty);
    });

    test('con credencial guardada, descarga xmltv.php con username/password del panel', () async {
      final store = FakeSecureCredentialStore();
      await store.save('s1', 'super-secreta');
      final calls = <Uri>[];
      final client = MockClient((request) async {
        calls.add(request.url);
        return http.Response('<?xml version="1.0" encoding="UTF-8"?><tv></tv>', 200);
      });
      final source = XmltvEpgSource(secureStore: store, client: client);

      final outcome = source.epgFor(xtreamSource(), now: now)!;

      await outcome.entries.drain<void>();
      expect(calls, hasLength(1));
      expect(calls.single.host, 'panel.example.com');
      expect(calls.single.path, '/xmltv.php');
      expect(calls.single.queryParameters, {'username': 'user', 'password': 'super-secreta'});
    });
  });

  group('con epgUrl', () {
    test('M3uUrlSourceConfig con epgUrl → no-null (M3U por URL)', () {
      final source = XmltvEpgSource(secureStore: FakeSecureCredentialStore());
      final outcome = source.epgFor(
        m3uUrlSource(epgUrl: Uri.parse('http://example.com/guide.xml')),
        now: now,
      );
      expect(outcome, isNotNull);
    });

    test('M3uFileSourceConfig con epgUrl → no-null (M3U por fichero, guía '
        'siempre es una URL)', () {
      final source = XmltvEpgSource(secureStore: FakeSecureCredentialStore());
      final outcome = source.epgFor(
        m3uFileSource(epgUrl: Uri.parse('http://example.com/guide.xml.gz')),
        now: now,
      );
      expect(outcome, isNotNull);
    });
  });
}
