import 'package:iptv_core/iptv_core.dart';

import '../xmltv/xmltv_entry.dart';
import '../xmltv/xmltv_window.dart';
import 'xtream_epg.dart';

/// Adapta `XtreamEpgListing` (por canal, `get_short_epg`/
/// `get_simple_data_table`) al lenguaje de entrada del escritor de ADR-008
/// (`XmltvEntry`/`EpgProgramme`) — S5.5 Bloque A3, **fallback bajo
/// demanda** para un canal concreto sin programas en drift, no la ruta
/// principal de ingesta (esa es `xmltv.php`, ver `XtreamUrlResolver
/// .xmltvUrl` + `EpgSource.epgFor`): N canales significarían N peticiones
/// de red, inviable como refresco de catálogo completo.
///
/// `DriftXmltvEpgWriter` no se toca ni se generaliza (P6/S5.5): esta
/// función solo produce lo que él ya sabe consumir, igual que
/// `parseXmltv` ya hace para XMLTV real.
///
/// [tvgId] lo aporta el llamador (`Channel.tvgId`) — `XtreamEpgListing` no
/// trae ninguno propio, y la clave primaria de `epg_programmes` es
/// `(tvgId, start)`. Si el canal no tiene `tvgId`, no se debe llamar a
/// esta función en absoluto (nada que persistir).
///
/// Política de descarte (análoga a `XmltvDiscard`, sin lista — igual de
/// silenciosa que la ventana de `parseXmltv`, esto nunca corre sobre un
/// volumen que justifique un informe): `start`/`end` ausentes, `end` no
/// posterior a `start`, o fuera de [window].
///
/// Normalización de zona horaria: `_parseTimestamp` (`xtream_epg.dart`)
/// devuelve `DateTime` **local** por la vía de texto
/// (`"YYYY-MM-DD HH:mm:ss"`) y **UTC** por la vía de epoch — se normaliza
/// aquí a UTC con `.toUtc()` antes de construir `EpgProgramme`, para que
/// tanto la comparación de ventana como la clave del escritor
/// (`_programmeKey`, que ya normaliza con `.toUtc()`) operen sobre el
/// mismo instante real sin depender de qué vía usó el panel.
Iterable<XmltvEntry> xtreamEpgToEntries({
  required String tvgId,
  required List<XtreamEpgListing> listings,
  required XmltvWindow window,
}) sync* {
  for (final listing in listings) {
    final start = listing.start;
    final end = listing.end;
    if (start == null || end == null) continue;
    if (!end.isAfter(start)) continue;
    if (!window.overlaps(start: start, stop: end)) continue;

    yield XmltvProgrammeEntry(
      EpgProgramme(
        tvgId: tvgId,
        start: start.toUtc(),
        stop: end.toUtc(),
        title: listing.title,
        description: listing.description,
      ),
    );
  }
}
