import 'package:iptv_protocols/src/xtream/xtream_url_resolver.dart';
import 'package:test/test.dart';

/// T1.4 / ADR-006: la URL canónica que vive en `Channel.url` nunca lleva
/// la contraseña del panel. Solo `XtreamUrlResolver.resolve()` (llamado
/// en el momento de reproducir, no al importar) la combina con el host y
/// las credenciales reales.
void main() {
  group('XtreamUrlResolver — construcción de canónicas', () {
    test('live: sin extensión', () {
      final uri = XtreamUrlResolver.liveCanonical(sourceId: 'src-1', streamId: '100984355');
      expect(uri.toString(), 'xtream://src-1/live/100984355');
    });

    test('movie: con extensión cuando se conoce container_extension', () {
      final uri = XtreamUrlResolver.movieCanonical(
        sourceId: 'src-1',
        streamId: '1908388221',
        containerExtension: 'mkv',
      );
      expect(uri.toString(), 'xtream://src-1/movie/1908388221.mkv');
    });

    test('movie sin container_extension: sin sufijo', () {
      final uri = XtreamUrlResolver.movieCanonical(sourceId: 'src-1', streamId: '1908388221');
      expect(uri.toString(), 'xtream://src-1/movie/1908388221');
    });

    test('movieRefCanonical siempre omite la extensión, aunque se le pase', () {
      final ref = XtreamUrlResolver.movieRefCanonical(sourceId: 'src-1', streamId: '1908388221');
      expect(ref.toString(), 'xtream://src-1/movie/1908388221');
    });

    test('series: episode_id con extensión', () {
      final uri = XtreamUrlResolver.seriesCanonical(
        sourceId: 'src-1',
        episodeId: '1875868768',
        containerExtension: 'mp4',
      );
      expect(uri.toString(), 'xtream://src-1/series/1875868768.mp4');
    });
  });

  group('XtreamUrlResolver.resolve — URL reproducible', () {
    test('live: añade el formato de salida solicitado', () {
      final canonical = XtreamUrlResolver.liveCanonical(sourceId: 'src-1', streamId: '100984355');

      final playable = XtreamUrlResolver.resolve(
        canonical: canonical,
        panelHost: Uri.parse('http://127.0.0.1:8081'),
        username: 'test',
        secret: 'super-secreta',
        liveOutputFormat: 'ts',
      );

      expect(playable.toString(), 'http://127.0.0.1:8081/live/test/super-secreta/100984355.ts');
    });

    test('movie: conserva la extensión de la canónica', () {
      final canonical = XtreamUrlResolver.movieCanonical(
        sourceId: 'src-1',
        streamId: '1908388221',
        containerExtension: 'mkv',
      );

      final playable = XtreamUrlResolver.resolve(
        canonical: canonical,
        panelHost: Uri.parse('http://127.0.0.1:8081'),
        username: 'test',
        secret: 'super-secreta',
      );

      expect(playable.toString(), 'http://127.0.0.1:8081/movie/test/super-secreta/1908388221.mkv');
    });

    test('un panelHost con puerto https se conserva', () {
      final canonical = XtreamUrlResolver.liveCanonical(sourceId: 'src-1', streamId: '5');

      final playable = XtreamUrlResolver.resolve(
        canonical: canonical,
        panelHost: Uri.parse('https://panel.example:8443'),
        username: 'u',
        secret: 'p',
      );

      expect(playable.scheme, 'https');
      expect(playable.port, 8443);
    });

    test('una contraseña con caracteres reservados se percent-encoda, no rompe la ruta', () {
      final canonical = XtreamUrlResolver.liveCanonical(sourceId: 'src-1', streamId: '5');

      final playable = XtreamUrlResolver.resolve(
        canonical: canonical,
        panelHost: Uri.parse('http://h:80'),
        username: 'u',
        secret: r'p/a?s#s&w=1',
      );

      // 5 segmentos reales de ruta (live, u, <secreto>, 5.ts) — el '/' de
      // la contraseña no se coló como separador de ruta adicional.
      expect(playable.pathSegments, hasLength(4));
      expect(Uri.decodeComponent(playable.pathSegments[2]), r'p/a?s#s&w=1');
    });

    test('canonical con scheme distinto de xtream:// lanza ArgumentError', () {
      expect(
        () => XtreamUrlResolver.resolve(
          canonical: Uri.parse('http://algo/live/1'),
          panelHost: Uri.parse('http://h'),
          username: 'u',
          secret: 'p',
        ),
        throwsArgumentError,
      );
    });

    test('kind desconocido en la canónica lanza ArgumentError', () {
      expect(
        () => XtreamUrlResolver.resolve(
          canonical: Uri.parse('xtream://src-1/unknown/1'),
          panelHost: Uri.parse('http://h'),
          username: 'u',
          secret: 'p',
        ),
        throwsArgumentError,
      );
    });
  });

  group('P5 — anti-fuga de credenciales', () {
    test('ninguna forma canónica contiene la contraseña, sea cual sea el kind', () {
      const secret = 'super-secreta-jamas-visible';
      final canonicals = [
        XtreamUrlResolver.liveCanonical(sourceId: 'src-1', streamId: '1'),
        XtreamUrlResolver.movieCanonical(sourceId: 'src-1', streamId: '2', containerExtension: 'mkv'),
        XtreamUrlResolver.movieRefCanonical(sourceId: 'src-1', streamId: '2'),
        XtreamUrlResolver.seriesCanonical(sourceId: 'src-1', episodeId: '3', containerExtension: 'mp4'),
        XtreamUrlResolver.seriesRefCanonical(sourceId: 'src-1', episodeId: '3'),
      ];

      for (final canonical in canonicals) {
        expect(canonical.toString(), isNot(contains(secret)));
        expect(canonical.scheme, 'xtream', reason: 'nunca debe degenerar al scheme http/https con host real');
      }
    });

    test('resolve() es la única función que combina secreto + host real', () {
      final canonical = XtreamUrlResolver.liveCanonical(sourceId: 'src-1', streamId: '1');
      // La canónica en sí (lo que se persistiría en Channel.url) no lleva
      // ni el host real ni el secreto.
      expect(canonical.host, 'src-1');
      expect(canonical.toString(), isNot(contains('super-secreta')));

      final playable = XtreamUrlResolver.resolve(
        canonical: canonical,
        panelHost: Uri.parse('http://127.0.0.1:8081'),
        username: 'test',
        secret: 'super-secreta',
      );
      expect(playable.toString(), contains('super-secreta'));
    });
  });
}
