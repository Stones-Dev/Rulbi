import 'package:iptv_app/features/player/playback_url_resolver.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:test/test.dart';

import '../sources/_helpers/fakes.dart';

/// `PlaybackUrlResolver` (S6, Bloque B) — calcado de
/// `xtream_epg_fallback_test.dart` en la forma de construir fuentes/fakes.
void main() {
  final now = DateTime.utc(2026, 8, 7);

  Channel m3uChannel() => Channel(
    ref: const ChannelRef(sourceId: 'm3u-1', key: 'canal-m3u'),
    sourceId: 'm3u-1',
    type: ContentType.live,
    name: 'Canal M3U',
    url: Uri.parse('http://cdn.example.com/live/canal.m3u8'),
  );

  Channel xtreamChannel({String kind = 'live', String id = '42'}) => Channel(
    ref: ChannelRef(sourceId: 'x-1', key: 'xtream://x-1/$kind/$id'),
    sourceId: 'x-1',
    type: kind == 'series-catalog' ? ContentType.series : ContentType.live,
    name: 'Canal Xtream',
    url: Uri.parse('xtream://x-1/$kind/$id'),
  );

  Source xtreamSource({String id = 'x-1', String username = 'user'}) => Source(
    id: id,
    config: XtreamSourceConfig(host: Uri.parse('http://panel.example.com'), username: username),
    name: 'Mi panel',
    updatedAt: now,
  );

  ({PlaybackUrlResolver resolver, FakeSourceRepository sources, FakeSecureCredentialStore secureStore})
  build() {
    final sources = FakeSourceRepository();
    final secureStore = FakeSecureCredentialStore();
    return (
      resolver: PlaybackUrlResolver(sources: sources, secureStore: secureStore),
      sources: sources,
      secureStore: secureStore,
    );
  }

  test('una fuente M3U pasa la URL intacta, sin consultar fuentes ni credenciales', () async {
    final setup = build();
    final channel = m3uChannel();

    final resolved = await setup.resolver.resolve(channel);

    expect(resolved, channel.url);
    expect(await setup.sources.getById('m3u-1'), isNull); // sanity: no se sembró
  });

  test('xtream:// se materializa con host + usuario + secreto del almacén', () async {
    final setup = build();
    await setup.sources.upsert(xtreamSource());
    await setup.secureStore.save('x-1', 'super-secreta');

    final resolved = await setup.resolver.resolve(xtreamChannel());

    expect(resolved, isNotNull);
    expect(resolved!.host, 'panel.example.com');
    expect(resolved.pathSegments, ['live', 'user', 'super-secreta', '42.ts']);
  });

  test('sin credencial guardada, no reproducible (null)', () async {
    final setup = build();
    await setup.sources.upsert(xtreamSource());
    // Sin guardar secreto.

    final resolved = await setup.resolver.resolve(xtreamChannel());

    expect(resolved, isNull);
  });

  test('fuente inexistente (borrada tras el import), no reproducible', () async {
    final setup = build();
    // Ninguna fuente registrada.

    final resolved = await setup.resolver.resolve(xtreamChannel());

    expect(resolved, isNull);
  });

  test('una serie del catálogo (series-catalog) nunca es reproducible, sin lanzar', () async {
    final setup = build();
    await setup.sources.upsert(xtreamSource());
    await setup.secureStore.save('x-1', 'super-secreta');

    final resolved = await setup.resolver.resolve(xtreamChannel(kind: 'series-catalog', id: '7'));

    expect(resolved, isNull);
  });

  test('un secreto con caracteres reservados se percent-encoda vía pathSegments, no se filtra roto', () async {
    final setup = build();
    await setup.sources.upsert(xtreamSource());
    await setup.secureStore.save('x-1', 'p@ss/word?with=reserved');

    final resolved = await setup.resolver.resolve(xtreamChannel());

    expect(resolved, isNotNull);
    // Uri.pathSegments ya decodifica lo que Uri.toString() percent-encodó
    // al construirlo — round-trip exacto, ninguna pérdida ni ruptura de
    // segmento por el '/' del secreto.
    expect(resolved!.pathSegments[2], 'p@ss/word?with=reserved');
  });

  test('movie/series conservan su extensión en el último segmento', () async {
    final setup = build();
    await setup.sources.upsert(xtreamSource());
    await setup.secureStore.save('x-1', 'secreta');

    final resolved = await setup.resolver.resolve(xtreamChannel(kind: 'movie', id: '99.mp4'));

    expect(resolved!.pathSegments.last, '99.mp4');
  });
}
