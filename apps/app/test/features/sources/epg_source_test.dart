import 'package:iptv_app/features/sources/epg_source.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:test/test.dart';

/// `XmltvEpgSource.epgFor` (S5 · Ola 2, ADR-008). Sin red real: `epgFor`
/// solo construye el `XmltvParseOutcome` — `parseXmltv` no empieza a
/// consumir bytes hasta que algo escucha `.entries` (ver su docstring), así
/// que comprobar `epgFor(...) != null` sin tocar `.entries` nunca dispara
/// una petición HTTP de verdad.
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
      final source = XmltvEpgSource();
      expect(source.epgFor(m3uUrlSource(), now: now), isNull);
    });

    test('M3uFileSourceConfig sin epgUrl → null', () {
      final source = XmltvEpgSource();
      expect(source.epgFor(m3uFileSource(), now: now), isNull);
    });
  });

  group('Xtream — fuera de alcance de ADR-008', () {
    test('XtreamSourceConfig → siempre null, sin mirar sus campos', () {
      final source = XmltvEpgSource();
      expect(source.epgFor(xtreamSource(), now: now), isNull);
    });
  });

  group('con epgUrl', () {
    test('M3uUrlSourceConfig con epgUrl → no-null (M3U por URL)', () {
      final source = XmltvEpgSource();
      final outcome = source.epgFor(
        m3uUrlSource(epgUrl: Uri.parse('http://example.com/guide.xml')),
        now: now,
      );
      expect(outcome, isNotNull);
    });

    test('M3uFileSourceConfig con epgUrl → no-null (M3U por fichero, guía '
        'siempre es una URL)', () {
      final source = XmltvEpgSource();
      final outcome = source.epgFor(
        m3uFileSource(epgUrl: Uri.parse('http://example.com/guide.xml.gz')),
        now: now,
      );
      expect(outcome, isNotNull);
    });
  });
}
