import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/features/channels/channel_page_cache.dart';
import 'package:iptv_core/iptv_core.dart';

import '_helpers/fake_channel_repository.dart';

/// `ChannelPageCache` (S5 · Ola 1, ui-spec §2.3): ventana con caché de
/// páginas sobre `ChannelRepository.channelsPage`/`countChannels` — la
/// base del `ListView.builder` de 100k canales. Dart puro, sin widgets:
/// se prueba directamente contra un repositorio falso.
void main() {
  Channel channelAt(int i) => Channel(
    ref: ChannelRef(sourceId: 's1', key: 'canal-$i'),
    sourceId: 's1',
    type: ContentType.live,
    name: 'Canal ${i.toString().padLeft(3, '0')}',
    url: Uri.parse('http://example.com/$i'),
  );

  const query = ChannelQuery(type: ContentType.live, sourceIds: {'s1'});

  test('init fija totalCount desde countChannels', () async {
    final repo = FakeChannelListRepository(
      channels: List.generate(37, channelAt),
    );
    final cache = ChannelPageCache(repository: repo, query: query, pageSize: 10);

    expect(cache.isInitialized, isFalse);
    await cache.init();

    expect(cache.isInitialized, isTrue);
    expect(cache.totalCount, 37);
  });

  test('itemAt devuelve null mientras la página no ha llegado y notifica al llegar', () async {
    final repo = FakeChannelListRepository(channels: List.generate(20, channelAt));
    final cache = ChannelPageCache(repository: repo, query: query, pageSize: 10);
    await cache.init();

    var notified = 0;
    cache.addListener(() => notified++);

    expect(cache.itemAt(0), isNull);
    expect(notified, 0);

    // La petición de página es async: hay que dejar correr el event loop.
    await Future<void>.delayed(Duration.zero);

    expect(notified, greaterThan(0));
    expect(cache.itemAt(0)?.name, 'Canal 000');
    expect(cache.itemAt(5)?.name, 'Canal 005');
  });

  test('no repite la petición de una página ya pendiente', () async {
    final repo = FakeChannelListRepository(channels: List.generate(20, channelAt));
    repo.pageDelay = Completer<void>().future; // nunca se resuelve en este test
    final cache = ChannelPageCache(repository: repo, query: query, pageSize: 10);
    await cache.init();

    // Tres índices de la misma página (0..9): una sola petición de página.
    cache.itemAt(0);
    cache.itemAt(3);
    cache.itemAt(9);

    expect(repo.pageRequests, [0]);
  });

  test('evicta páginas LRU cuando se supera maxCachedPages', () async {
    final repo = FakeChannelListRepository(channels: List.generate(50, channelAt));
    final cache = ChannelPageCache(
      repository: repo,
      query: query,
      pageSize: 10,
      maxCachedPages: 2,
    );
    await cache.init();

    // Carga páginas 0, 1, 2 en orden — con maxCachedPages=2, la página 0
    // (la menos usada recientemente) debe evictarse al llegar la 2.
    cache.itemAt(0);
    await Future<void>.delayed(Duration.zero);
    cache.itemAt(10);
    await Future<void>.delayed(Duration.zero);
    cache.itemAt(20);
    await Future<void>.delayed(Duration.zero);

    // La página 0 ya no está cacheada: pedirla de nuevo dispara otra
    // petición al repositorio.
    final requestsBefore = repo.pageRequests.length;
    expect(cache.itemAt(0), isNull);
    expect(repo.pageRequests.length, requestsBefore + 1);
  });

  test('tocar un índice de una página cacheada la marca como reciente (no se evicta)', () async {
    final repo = FakeChannelListRepository(channels: List.generate(50, channelAt));
    final cache = ChannelPageCache(
      repository: repo,
      query: query,
      pageSize: 10,
      maxCachedPages: 2,
    );
    await cache.init();

    cache.itemAt(0); // página 0
    await Future<void>.delayed(Duration.zero);
    cache.itemAt(10); // página 1
    await Future<void>.delayed(Duration.zero);

    // Vuelve a tocar la página 0 antes de cargar una tercera: debe pasar
    // a ser la más reciente, así que la 1 (no la 0) es la que se evicta.
    cache.itemAt(0);
    cache.itemAt(20); // página 2
    await Future<void>.delayed(Duration.zero);

    final requestsBefore = repo.pageRequests.length;
    expect(cache.itemAt(0), isNotNull); // sigue en caché
    expect(repo.pageRequests.length, requestsBefore); // sin nueva petición

    expect(cache.itemAt(10), isNull); // evictada
    expect(repo.pageRequests.length, requestsBefore + 1);
  });

  test('un índice fuera de rango (última página parcial) no revienta', () async {
    final repo = FakeChannelListRepository(channels: List.generate(23, channelAt));
    final cache = ChannelPageCache(repository: repo, query: query, pageSize: 10);
    await cache.init();

    expect(cache.totalCount, 23);
    cache.itemAt(20);
    await Future<void>.delayed(Duration.zero);

    expect(cache.itemAt(22)?.name, 'Canal 022');
    // Los índices 23-29 no existen en la última página (parcial, 3 filas).
    expect(cache.itemAt(23), isNull);
  });
}
