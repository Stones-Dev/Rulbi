import 'package:iptv_protocols/src/xtream/xtream_client.dart';
import 'package:iptv_protocols/src/xtream/xtream_epg.dart';
import 'package:iptv_protocols/src/xtream/xtream_failure.dart';
import 'package:test/test.dart';

import 'support/fake_xtream_transport.dart';

/// T1.4: `get_short_epg`/`get_simple_data_table` no estaban entre los 9
/// fixtures reales de T1.1 — cubiertos aquí con sintéticos documentados
/// (`test/fixtures/xtream/synthetic/README.md`). Xtream Codes documenta
/// `title`/`description` en base64, pero algunos paneles mandan texto
/// plano — ninguno de los dos debe producir una excepción.
void main() {
  group('XtreamClient.shortEpg — título/descripción base64 vs claro vs roto', () {
    test('base64 válido se decodifica', () async {
      final client = _clientWith('get_short_epg_base64.json');

      final result = await client.shortEpg('100984355');

      final listings = (result as XtreamOk<List<XtreamEpgListing>>).value;
      expect(listings.single.title, 'Telediario 21h');
      expect(listings.single.description, 'Resumen de la actualidad nacional e internacional.');
      expect(listings.single.start, DateTime.parse('2026-07-31T21:00:00'));
    });

    test('texto plano (panel no conformante) se conserva tal cual', () async {
      final client = _clientWith('get_short_epg_plain.json');

      final result = await client.shortEpg('100984355');

      final listings = (result as XtreamOk<List<XtreamEpgListing>>).value;
      expect(listings.single.title, 'Telediario 21h');
      expect(listings.single.description, 'Resumen de la actualidad nacional e internacional.');
    });

    test('base64 roto (bytes no-UTF8 y caracteres fuera de alfabeto) no lanza, emite crudo', () async {
      final client = _clientWith('get_short_epg_broken_base64.json');

      final result = await client.shortEpg('100984355');

      final listings = (result as XtreamOk<List<XtreamEpgListing>>).value;
      expect(listings.single.title, '/////w==', reason: 'base64 sintácticamente válido pero UTF-8 inválido -> texto crudo');
      expect(
        listings.single.description,
        contains('fuera del alfabeto'),
        reason: 'caracteres inválidos de base64 -> texto crudo, nunca excepción',
      );
    });

    test('canal sin epg_listings -> lista vacía, no error', () async {
      final fake = FakeXtreamTransport()..enqueue('get_short_epg', jsonResponse({}));
      final client = XtreamClient(
        host: Uri.parse('http://127.0.0.1:8081'),
        username: 'test',
        password: 'test',
        transport: fake,
      );

      final result = await client.shortEpg('1');

      expect((result as XtreamOk<List<XtreamEpgListing>>).value, isEmpty);
    });
  });

  group('XtreamClient.simpleDataTable', () {
    test('mismo formato de sobre que get_short_epg', () async {
      final fake = FakeXtreamTransport(fixturesDir: 'test/fixtures/xtream/synthetic')
        ..enqueue(
          'get_simple_data_table',
          jsonResponse({
            'epg_listings': [
              {'id': '1', 'title': 'VGVzdA==', 'start': '2026-07-31 10:00:00', 'end': '2026-07-31 11:00:00'},
            ],
          }),
        );
      final client = XtreamClient(
        host: Uri.parse('http://127.0.0.1:8081'),
        username: 'test',
        password: 'test',
        transport: fake,
      );

      final result = await client.simpleDataTable('1');

      final listings = (result as XtreamOk<List<XtreamEpgListing>>).value;
      expect(listings.single.title, 'Test');
    });
  });
}

XtreamClient _clientWith(String fixture) => XtreamClient(
  host: Uri.parse('http://127.0.0.1:8081'),
  username: 'test',
  password: 'test',
  transport: FakeXtreamTransport(
    fixturesDir: 'test/fixtures/xtream/synthetic',
    actionToFixture: {'get_short_epg': fixture},
  ),
);
