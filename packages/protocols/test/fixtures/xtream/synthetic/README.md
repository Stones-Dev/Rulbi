# Fixtures Xtream sintéticos — T1.4

Complementan `dialect_o0zz/` (9 dumps reales de T1.1) para dos cosas que
esos dumps no cubren: la acción de EPG del panel (`get_short_epg`/
`get_simple_data_table`, no capturada en T1.1 — ver README de
`test/fixtures/xtream/`) y anomalías de dialecto que ningún panel real
observado producía pero que la documentación pública de Xtream Codes
(`xtream-ui.org`) y la práctica de otros clientes documentan como reales.
Mismo espíritu que `m3u/edge_cases/`: sintéticos, documentados uno a uno,
nunca presentados como capturas reales.

## `get_short_epg_*.json` — título/descripción en base64 vs claro vs roto

Xtream Codes documenta `title`/`description` de `get_short_epg` y
`get_simple_data_table` codificados en **base64** — pero en la práctica no
todos los paneles lo respetan; algunos mandan texto plano directamente.
Ambas formas son reales según distintos clientes Xtream de código abierto
que tratan este campo de forma tolerante. `XtreamEpgListing.fromJson`
intenta decodificar como base64 + UTF-8 y cae al texto crudo si falla en
cualquiera de los dos pasos — nunca lanza.

| Archivo | Qué cubre |
|---|---|
| `get_short_epg_base64.json` | Caso documentado: `title`/`description` en base64 válido (`VGVsZWRpYXJpbyAyMWg=` → "Telediario 21h"). |
| `get_short_epg_plain.json` | Panel no conformante: mismo contenido pero en texto plano, sin codificar. |
| `get_short_epg_broken_base64.json` | Dos variantes de "roto" en un mismo fixture: `title` (`/////w==`) es base64 *sintácticamente válido* pero decodifica a bytes que no son UTF-8 válido (falla en el segundo paso); `description` contiene caracteres fuera del alfabeto base64 (falla en el primer paso, `FormatException` de `base64.decode`). Ambos casos deben emitir el texto crudo tal cual, sin excepción. |

Todos comparten la misma estructura de sobre (`epg_listings: [...]`,
`start`/`end` como `"YYYY-MM-DD HH:mm:ss"` + `start_timestamp`/
`stop_timestamp` como epoch de respaldo) documentada en `xtream-ui.org`
para `player_api.php?action=get_short_epg`.
