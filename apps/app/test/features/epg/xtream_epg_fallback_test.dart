import 'dart:convert';

import 'package:iptv_app/features/epg/xtream_epg_fallback.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_protocols/iptv_protocols.dart';
import 'package:test/test.dart';

import '../../_helpers/fake_epg_repository.dart';
import '../sources/_helpers/fakes.dart';

/// `XtreamEpgFallback.ensureEpgFor` (S5.5, Bloque A3) — fallback bajo
/// demanda cuando `xmltv.php` (ruta principal) no cubre un canal. Escribe
/// de verdad en drift a través de `XmltvEpgWriter` (fake que hace un
/// `await for` real, mismo criterio que `xmltv_epg_writer_test.dart`), no
/// solo "no lanza excepción".
void main() {
  final now = DateTime.utc(2026, 8, 7, 12);

  Channel xtreamChannel({
    String? tvgId = 'canal.1',
    String? streamId = '42',
    ContentType type = ContentType.live,
  }) => Channel(
    ref: const ChannelRef(sourceId: 's1', key: 'xtream://s1/live/42'),
    sourceId: 's1',
    type: type,
    name: 'Canal 1',
    url: Uri.parse('xtream://s1/live/42'),
    tvgId: tvgId,
    metadata: {'x-xtream-stream-id': ?streamId},
  );

  Source xtreamSource() => Source(
    id: 's1',
    config: XtreamSourceConfig(host: Uri.parse('http://panel.example.com'), username: 'user'),
    name: 'Mi panel',
    updatedAt: now,
  );

  ({
    XtreamEpgFallback fallback,
    FakeEpgRepository epg,
    FakeXmltvEpgWriter writer,
    FakeSourceRepository sources,
    FakeSecureCredentialStore secureStore,
  })
  build({required _FakeXtreamTransport transport}) {
    final epg = FakeEpgRepository();
    final writer = FakeXmltvEpgWriter();
    final sources = FakeSourceRepository();
    final secureStore = FakeSecureCredentialStore();
    final fallback = XtreamEpgFallback(
      epgRepository: epg,
      writer: writer,
      sources: sources,
      secureStore: secureStore,
      clientFactory: ({required host, required username, required password}) =>
          XtreamClient(host: host, username: username, password: password, transport: transport),
    );
    return (fallback: fallback, epg: epg, writer: writer, sources: sources, secureStore: secureStore);
  }

  test('canal no-live nunca dispara el fallback', () async {
    final setup = build(transport: _FakeXtreamTransport());
    final channel = xtreamChannel(type: ContentType.vod);

    final wrote = await setup.fallback.ensureEpgFor(channel, now: now);

    expect(wrote, isFalse);
    expect(setup.writer.writeCalls, 0);
  });

  test('canal sin tvgId nunca dispara el fallback', () async {
    final setup = build(transport: _FakeXtreamTransport());

    final wrote = await setup.fallback.ensureEpgFor(xtreamChannel(tvgId: null), now: now);

    expect(wrote, isFalse);
    expect(setup.writer.writeCalls, 0);
  });

  test('canal sin x-xtream-stream-id (no viene de Xtream) nunca dispara el fallback', () async {
    final setup = build(transport: _FakeXtreamTransport());

    final wrote = await setup.fallback.ensureEpgFor(xtreamChannel(streamId: null), now: now);

    expect(wrote, isFalse);
    expect(setup.writer.writeCalls, 0);
  });

  test('canal que ya tiene programas en la ventana no vuelve a pedir nada', () async {
    final transport = _FakeXtreamTransport();
    final setup = build(transport: transport);
    setup.epg.seed(
      EpgProgramme(
        tvgId: 'canal.1',
        start: now.subtract(const Duration(minutes: 10)),
        stop: now.add(const Duration(minutes: 20)),
        title: 'Ya en drift',
      ),
    );

    final wrote = await setup.fallback.ensureEpgFor(xtreamChannel(), now: now);

    expect(wrote, isFalse);
    expect(transport.calls, isEmpty);
    expect(setup.writer.writeCalls, 0);
  });

  test('sin fuente encontrada, o fuente no-Xtream, no dispara el fallback', () async {
    final setup = build(transport: _FakeXtreamTransport());
    // Ninguna fuente registrada en FakeSourceRepository (getById -> null).

    final wrote = await setup.fallback.ensureEpgFor(xtreamChannel(), now: now);

    expect(wrote, isFalse);
    expect(setup.writer.writeCalls, 0);
  });

  test('sin credencial guardada, no dispara petición y no escribe', () async {
    final setup = build(transport: _FakeXtreamTransport());
    await setup.sources.upsert(xtreamSource());
    // Sin guardar secreto en setup.secureStore.

    final wrote = await setup.fallback.ensureEpgFor(xtreamChannel(), now: now);

    expect(wrote, isFalse);
    expect(setup.writer.writeCalls, 0);
  });

  test('camino feliz: pide simpleDataTable del stream_id y escribe vía el escritor de ADR-008', () async {
    final transport = _FakeXtreamTransport()
      ..respond(
        'get_simple_data_table',
        jsonEncode({
          'epg_listings': [
            {
              'id': '1',
              'title': base64.encode(utf8.encode('Telediario')),
              'start': '2026-08-07 21:00:00',
              'end': '2026-08-07 22:00:00',
            },
          ],
        }),
      );
    final setup = build(transport: transport);
    await setup.sources.upsert(xtreamSource());
    await setup.secureStore.save('s1', 'super-secreta');

    final wrote = await setup.fallback.ensureEpgFor(xtreamChannel(), now: now);

    expect(wrote, isTrue);
    expect(transport.calls, hasLength(1));
    expect(transport.calls.single.queryParameters['stream_id'], '42');
    expect(setup.writer.writeCalls, 1);
    expect(setup.writer.written, hasLength(1));
    final entry = setup.writer.written.single as XmltvProgrammeEntry;
    expect(entry.programme.tvgId, 'canal.1');
    expect(entry.programme.title, 'Telediario');
  });

  test('el panel devuelve error -> no escribe, no lanza', () async {
    final transport = _FakeXtreamTransport()..respondWithStatus('get_simple_data_table', 500);
    final setup = build(transport: transport);
    await setup.sources.upsert(xtreamSource());
    await setup.secureStore.save('s1', 'super-secreta');

    final wrote = await setup.fallback.ensureEpgFor(xtreamChannel(), now: now);

    expect(wrote, isFalse);
    expect(setup.writer.writeCalls, 0);
  });

  test('el panel devuelve solo entradas fuera de ventana -> no escribe (lista vacía tras adaptar)', () async {
    final transport = _FakeXtreamTransport()
      ..respond(
        'get_simple_data_table',
        jsonEncode({
          'epg_listings': [
            {
              'id': '1',
              'title': base64.encode(utf8.encode('Muy futuro')),
              'start': '2030-01-01 10:00:00',
              'end': '2030-01-01 11:00:00',
            },
          ],
        }),
      );
    final setup = build(transport: transport);
    await setup.sources.upsert(xtreamSource());
    await setup.secureStore.save('s1', 'super-secreta');

    final wrote = await setup.fallback.ensureEpgFor(xtreamChannel(), now: now);

    expect(wrote, isFalse);
    expect(setup.writer.writeCalls, 0);
  });
}

/// `XtreamTransport` en memoria, local a este test — no se puede reusar
/// el `FakeXtreamTransport` de `packages/protocols` (helper interno de
/// ese paquete, no exportado). Suficiente para `simpleDataTable`: registra
/// la última URL pedida por acción y permite fijar cuerpo/estado.
final class _FakeXtreamTransport implements XtreamTransport {
  final Map<String, String> _bodyByAction = {};
  final Map<String, int> _statusByAction = {};
  final List<Uri> calls = [];

  void respond(String action, String body) => _bodyByAction[action] = body;

  void respondWithStatus(String action, int statusCode) => _statusByAction[action] = statusCode;

  @override
  Future<XtreamHttpResponse> get(Uri url) async {
    final action = url.queryParameters['action'] ?? '';
    calls.add(url);
    final statusCode = _statusByAction[action] ?? 200;
    final body = _bodyByAction[action] ?? '{}';
    return XtreamHttpResponse(statusCode: statusCode, bodyBytes: utf8.encode(body), contentType: 'application/json');
  }
}
