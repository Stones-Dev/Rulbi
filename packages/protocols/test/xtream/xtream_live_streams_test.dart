import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_protocols/src/xtream/xtream_client.dart';
import 'package:iptv_protocols/src/xtream/xtream_failure.dart';
import 'package:iptv_protocols/src/xtream/xtream_mapper.dart';
import 'package:iptv_protocols/src/xtream/xtream_stream.dart';
import 'package:test/test.dart';

import 'support/fake_xtream_transport.dart';

void main() {
  group('XtreamClient.liveStreams (fixture real: 2 canales)', () {
    test('parsea los 2 canales, uno con icono y otro sin', () async {
      final client = _client(FakeXtreamTransport());

      final result = await client.liveStreams();

      final streams = (result as XtreamOk<List<XtreamLiveStream>>).value;
      expect(streams, hasLength(2));

      final canalUno = streams.firstWhere((s) => s.name == 'Canal Uno HD');
      expect(canalUno.streamId, 100984355);
      expect(canalUno.epgChannelId, 'canal1.test');
      expect(canalUno.streamIcon, 'https://example.com/canal1.png');
      expect(canalUno.categoryId, '1544024662');

      final canalDos = streams.firstWhere((s) => s.name == 'Canal Dos');
      expect(canalDos.streamIcon, isNull, reason: 'stream_icon: null en el fixture real');
    });

    test('category_id se manda como query param cuando se filtra', () async {
      final fake = FakeXtreamTransport();
      final client = _client(fake);

      await client.liveStreams(categoryId: '1544024662');

      expect(fake.callCount('get_live_streams'), 1);
    });
  });

  group('XtreamMapper.liveStreamToChannel', () {
    test('epg_channel_id presente -> ChannelRef derivado del tvg-id, no de la URL', () {
      const stream = XtreamLiveStream(
        streamId: 100984355,
        name: 'Canal Uno HD',
        categoryId: '1544024662',
        epgChannelId: 'canal1.test',
        streamIcon: 'https://example.com/canal1.png',
      );

      final channel = XtreamMapper.liveStreamToChannel(
        sourceId: 'src-1',
        stream: stream,
        categoryNames: {'1544024662': 'Noticias'},
      );

      expect(channel.type, ContentType.live);
      expect(channel.sourceId, 'src-1');
      expect(channel.tvgId, 'canal1.test');
      expect(channel.url.toString(), 'xtream://src-1/live/100984355');
      expect(channel.logo, Uri.parse('https://example.com/canal1.png'));
      expect(
        channel.ref,
        ChannelRef.derive(sourceId: 'src-1', tvgId: 'canal1.test', url: null, name: 'Canal Uno HD'),
      );
      expect(channel.metadata['x-xtream-stream-id'], '100984355');
    });

    test('sin epg_channel_id -> ChannelRef cae a la URL canónica (nunca a la reproducible)', () {
      const stream = XtreamLiveStream(streamId: 42, name: 'Sin EPG', categoryId: null);

      final channel = XtreamMapper.liveStreamToChannel(sourceId: 'src-1', stream: stream);

      final expectedRef = ChannelRef.derive(
        sourceId: 'src-1',
        tvgId: null,
        url: 'xtream://src-1/live/42',
        name: 'Sin EPG',
      );
      expect(channel.ref, expectedRef);
      expect(channel.categoryId, isNull);
    });

    test('category_id sin nombre en el mapa se degrada al id crudo, no se pierde la categoría', () {
      const stream = XtreamLiveStream(streamId: 1, name: 'X', categoryId: '999');

      final channel = XtreamMapper.liveStreamToChannel(sourceId: 'src-1', stream: stream);

      expect(channel.categoryId, Category.derive(sourceId: 'src-1', type: ContentType.live, name: '999').id);
    });

    test('stream_icon vacío/null nunca produce un Uri inválido', () {
      const stream = XtreamLiveStream(streamId: 1, name: 'X', categoryId: null, streamIcon: null);
      final channel = XtreamMapper.liveStreamToChannel(sourceId: 'src-1', stream: stream);
      expect(channel.logo, isNull);
    });
  });
}

XtreamClient _client(FakeXtreamTransport transport) => XtreamClient(
  host: Uri.parse('http://127.0.0.1:8081'),
  username: 'test',
  password: 'test',
  transport: transport,
);
