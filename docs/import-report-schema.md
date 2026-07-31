# Informe de descartes — formato JSON (T1.9, extendido a Xtream en T1.4)

**Tarea**: "Informe de descartes" (*Tareas — IPTV*, Sprint 1). **Hecho
cuando** (Notion, enmendado en T1.9 — ver `handoff.md`): "cada entrada
descartada aparece con motivo y localización (número de línea en M3U;
ordinal + offset de carácter en XMLTV, que no puede dar un número de línea
honesto)".

`ImportReport` (M3U) y `XmltvImportReport` (XMLTV) ya existían desde T1.2/
T1.3; `XtreamImportReport` (Xtream) se añadió en T1.4 — cada parser lo
produce internamente y nunca lanza una excepción por una entrada rota
(P7). T1.9 es (1) que `ManageSources`/`ChannelRepository` devuelvan
también el recuento del upsert (`SourceImportStats`, T1.6b), y (2) un
formato de serialización JSON estable para que la UI de Fase 2 lo consuma
sin tener que enlazar contra `packages/protocols`/`packages/core`
directamente (útil, por ejemplo, si el informe se persiste o se manda a
través de `pairing`).

## Por qué piezas separadas, no un solo tipo

Regla de capas del proyecto (P6, CLAUDE.md): el dominio (`core`) no conoce
vocabulario de M3U/XMLTV/Xtream, y `protocols` no sabe qué es un upsert
diferencial contra SQLite. Cada capa serializa su propia mitad:

- `ImportReport.toJson()` / `XmltvImportReport.toJson()` /
  `XtreamImportReport.toJson()` — viven en `packages/protocols`, un
  discriminador `kind` (`"m3u"` | `"xmltv"` | `"xtream"`) distingue cuál es
  cuál.
- `SourceImportStats.toJson()` — vive en `packages/core`
  (`packages/core/lib/src/ports/channel_repository.dart`), es el recuento
  del diff (`ChannelRepository.importSourceContent`).

Quien compone el sobre completo (la app, Fase 2) simplemente junta las dos
piezas — ninguna capa necesita conocer a la otra para producir la suya.

## El sobre (envelope)

```json
{
  "schemaVersion": 1,
  "sourceId": "s1",
  "importedAt": "2026-07-30T18:04:11.000Z",
  "parser": { "kind": "m3u" | "xmltv" | "xtream", "...": "..." },
  "upsert": { "...": "..." }
}
```

- `schemaVersion` — de este sobre compuesto, no de ninguna de las piezas
  por separado (cada una ya lleva sus propios campos; si alguna cambia de
  forma incompatible, se sube este número).
- `sourceId`/`importedAt` — los añade quien compone el sobre (la app), no
  ninguna de las piezas — ellas no conocen la fuente que las produjo.
- `parser` — el resultado de `ImportReport.toJson()`,
  `XmltvImportReport.toJson()` o `XtreamImportReport.toJson()`, tal cual.
- `upsert` — el resultado de `SourceImportStats.toJson()`, tal cual.
  Aplica a M3U y a Xtream (ambos producen un `Stream<Channel>` que pasa
  por `ManageSources`). Falta para XMLTV hasta que exista la tarea de
  escritura EPG a `data` (S2, "Ventana y purga EPG") — un XMLTV no pasa
  por `ManageSources` (ver
  `packages/core/lib/src/use_cases/manage_sources.dart`).

## `parser.kind = "m3u"`

Campos de `ImportReport.toJson()`
(`packages/protocols/lib/src/m3u/import_report.dart`):

| Campo | Tipo | Significado |
|---|---|---|
| `kind` | `"m3u"` | Discriminador. |
| `parsed` | `int` | Canales emitidos con éxito. |
| `discardedCount` | `int` | Líneas descartadas (== `discarded.length`; M3U no tiene cap, a diferencia de XMLTV). |
| `discarded` | `DiscardedLine[]` | En el orden en que aparecieron en el origen. |

`DiscardedLine.toJson()`:

| Campo | Tipo | Significado |
|---|---|---|
| `lineNumber` | `int` | 1-based, tal como aparece en el archivo de origen. |
| `rawLine` | `string` | La línea completa descartada. |
| `reason` | `string` | Motivo legible, en español (mismo idioma que el resto del código/UI del proyecto). |

### Ejemplo real

Del fixture ya comiteado `packages/protocols/test/fixtures/m3u/edge_cases/
pipe_user_agent_referer.m3u` — reproduce el ejemplo *literal* del issue
[`4gray/iptvnator#57`](https://github.com/4gray/iptvnator/issues/57): un
solo `#EXTINF` seguido de dos líneas de URL (M3U mal formado a propósito).
La primera URL cierra el `#EXTINF` abierto; la segunda, sin `#EXTINF`
propio, se descarta — no se le inventa una identidad de canal (ver
`packages/protocols/test/m3u/import_report_json_test.dart` para el golden
completo, verificado contra la salida real del parser, no escrito a mano):

```json
{
  "kind": "m3u",
  "parsed": 1,
  "discardedCount": 1,
  "discarded": [
    {
      "lineNumber": 8,
      "rawLine": "https://www.streamaway.net/fra/histo/index.m3u8|Referer=https://www.streamaway.net/fr/Histoire-fr.php",
      "reason": "URL sin #EXTINF previo"
    }
  ]
}
```

## `parser.kind = "xmltv"`

Campos de `XmltvImportReport.toJson()`
(`packages/protocols/lib/src/xmltv/xmltv_report.dart`) — **no** reutiliza
la forma de M3U a propósito (decisión de diseño de T1.3, justificada en el
propio código): un parser de eventos por chunks no puede dar un número de
línea honesto, y XMLTV necesita contadores (fuera de ventana, refs de canal
desconocidas) que en forma de lista también reventarían la memoria con un
XMLTV real de cientos de MB.

| Campo | Tipo | Significado |
|---|---|---|
| `kind` | `"xmltv"` | Discriminador. |
| `parsedChannels` | `int` | `<channel>` emitidos con éxito. |
| `parsedProgrammes` | `int` | `<programme>` emitidos con éxito (dentro de ventana). |
| `outOfWindowProgrammes` | `int` | Programas bien formados pero fuera de la ventana temporal — **no** es un descarte (P7), por eso es un contador y no una lista. |
| `assumedUtcDates` | `int` | Programas cuya fecha no traía offset horario (se asumió UTC); se emiten igual. |
| `unknownChannelRefs` | `{ [channelId: string]: int }` | `channel` de un `<programme>` no declarado en ningún `<channel>` del propio XMLTV — el programa se emite igual (el join real es contra `tvg-id` del M3U). |
| `unknownTags` | `{ [tagName: string]: int }` | Etiquetas ignoradas (hijos de `<tv>` que no son `<channel>`/`<programme>`, o hijos desconocidos dentro de uno de esos dos). |
| `discardedCount` | `int` | Total real de descartes, incluso si supera el cap. |
| `discardedTruncated` | `bool` | `true` si `discardedCount` superó el tamaño de `discarded` (cap = 1000). |
| `discarded` | `XmltvDiscard[]` | Los primeros 1000 descartes reales (fallos de parseo), en orden. |

`XmltvDiscard.toJson()`:

| Campo | Tipo | Significado |
|---|---|---|
| `entryIndex` | `int` | Ordinal 0-based del `<channel>`/`<programme>` dentro del documento — **no** un número de línea (ver justificación arriba). Reproducible entre corridas del mismo archivo. |
| `charOffset` | `int \| null` | Offset de carácter en el documento decodificado. |
| `channelId` | `string \| null` | Canal del `<programme>` afectado, si se conoce. |
| `rawSnippet` | `string` | Recorte del contenido crudo relevante, acotado a un tamaño legible. |
| `reason` | `string` | Motivo legible. |

### Ejemplo real

Del estrés de 193 MB de T1.3 (`epgshare01_all_sources.xml.gz`,
`docs/bench/T1.3-xmltv-stress.md`): 573 descartes, el 100 % de una sola
categoría, todos del canal `MUSIC.BOX.00s.musicbox` — su generador emite
`stop="...MM=60..."` (minuto 60, fuera de rango 0-59) en vez de rodar al
minuto 00 de la hora siguiente; `parseXmltvDate`
(`packages/protocols/lib/src/xmltv/xmltv_date.dart`) lo rechaza por diseño.
Reproducido con un fragmento mínimo (no los 193 MB reales) en
`packages/protocols/test/xmltv/xmltv_report_json_test.dart`:

```json
{
  "kind": "xmltv",
  "parsedChannels": 1,
  "parsedProgrammes": 0,
  "outOfWindowProgrammes": 0,
  "assumedUtcDates": 0,
  "unknownChannelRefs": {},
  "unknownTags": {},
  "discardedCount": 1,
  "discardedTruncated": false,
  "discarded": [
    {
      "entryIndex": 1,
      "charOffset": 99,
      "channelId": "MUSIC.BOX.00s.musicbox",
      "rawSnippet": "",
      "reason": "stop ilegible: \"20260730056000 +0000\""
    }
  ]
}
```

(`entryIndex`/`charOffset` son los valores reales que produce este
fragmento mínimo exacto, verificados por test — `rawSnippet` vacío porque
`parseXmltvCore` no rellena un recorte para este tipo de descarte. El
documento de 193 MB real de producción tendría un `entryIndex`/`charOffset`
mayores, propios de su posición dentro de ese archivo — lo estable y
verificado es la *forma* del JSON y el `reason`, no un offset absoluto que
depende del tamaño del documento.)

## `parser.kind = "xtream"`

Campos de `XtreamImportReport.toJson()`
(`packages/protocols/lib/src/xtream/xtream_import_report.dart`) — producido
por `XtreamClient.importChannels()` (T1.4). No reutiliza la forma de M3U ni
la de XMLTV: `discarded` aquí no son entradas individuales dentro de una
lista bien formada (esas ya se toleran campo a campo dentro de cada
`fromJson`, sin dejar rastro — ver batería de dialectos de T1.4), sino
**acciones completas de `player_api.php` que fallaron** (p. ej. un 500 en
`get_vod_streams` a mitad de import) — el import de live/VOD sigue
adelante con lo que sí respondió (P7).

| Campo | Tipo | Significado |
|---|---|---|
| `kind` | `"xtream"` | Discriminador. |
| `parsedLive` | `int` | `Channel(type: live)` emitidos con éxito. |
| `parsedVod` | `int` | `Channel(type: vod)` emitidos con éxito. |
| `discardedCount` | `int` | Total real de acciones fallidas, incluso si supera el cap (1000, mismo criterio que XMLTV). |
| `discarded` | `XtreamDiscard[]` | En el orden en que ocurrieron. |

`XtreamDiscard.toJson()`:

| Campo | Tipo | Significado |
|---|---|---|
| `action` | `string` | Action de `player_api.php` que falló (`get_live_categories`, `get_vod_streams`, ...). |
| `reason` | `string` | `toString()` del `XtreamFailure` correspondiente (p. ej. `"XtreamHttpFailure(500)"`) — nunca contiene la contraseña del panel (ADR-006/P5, ningún `XtreamFailure` la lleva). |

Series/temporadas/episodios **no** entran en este informe: `get_series` no
trae episodios (un import completo no puede pedir `get_series_info` por
cada serie de un panel grande), así que se piden bajo demanda al abrir la
ficha y no forman parte de `importChannels()`.

### Ejemplo real

Contra los 9 fixtures de T1.1 (`o0Zz/xtreamcodeserver`, ver
`packages/protocols/test/fixtures/xtream/dialect_o0zz/`): 2 canales live +
1 película, sin descartes (`packages/protocols/test/xtream/xtream_report_json_test.dart`,
`xtream_import_test.dart`):

```json
{
  "kind": "xtream",
  "parsedLive": 2,
  "parsedVod": 1,
  "discardedCount": 0,
  "discarded": []
}
```

Con un fallo simulado en `get_vod_streams` (500), el import de live sigue
adelante:

```json
{
  "kind": "xtream",
  "parsedLive": 2,
  "parsedVod": 0,
  "discardedCount": 1,
  "discarded": [
    { "action": "get_vod_streams", "reason": "XtreamHttpFailure(500)" }
  ]
}
```

## `upsert` — `SourceImportStats.toJson()`

Campos (`packages/core/lib/src/ports/channel_repository.dart`) — vocabulario
de dominio, no de M3U/XMLTV, por eso vive en `core`:

| Campo | Tipo | Significado |
|---|---|---|
| `inserted` | `int` | Canales nuevos (su `ChannelRef` no existía para esta fuente). |
| `updated` | `int` | Canales existentes cuyo contenido cambió. |
| `unchanged` | `int` | Canales existentes cuyo contenido no cambió — no generan ningún `UPDATE`. |
| `tombstoned` | `int` | Canales que existían y no aparecieron en este import (se marcan `deletedAt`, no se borran). |
| `resurrected` | `int` | Canales que estaban tumbados y reaparecieron. |
| `duplicateRefs` | `int` | Canales con el mismo `ChannelRef` repetidos dentro del *mismo* import (p. ej. dos entradas M3U sin `tvg-id` que normalizan al mismo nombre) — gana el último; es lo que hace accionable el informe ante una lista con identidades colisionando. |

### Ejemplo

```json
{
  "inserted": 128,
  "updated": 12,
  "unchanged": 13420,
  "tombstoned": 3,
  "resurrected": 1,
  "duplicateRefs": 2
}
```

## Estabilidad

Las cuatro piezas (`ImportReport`, `XmltvImportReport`, `XtreamImportReport`,
`SourceImportStats`) serializan sus claves en un orden fijo (no dependen de
`hashCode`/orden de iteración de ningún `Map` interno de Dart) y no
incluyen ningún `DateTime.now()` propio — el mismo informe produce siempre
el mismo JSON entre corridas y entre versiones del SDK de Dart. Verificado
con tests de round-trip (`toJson` → `fromJson` → `toJson` idéntico) en las
baterías citadas arriba.
