# Fixtures M3U — T1.1

Golden files reales para el parser M3U (`packages/protocols`), recolectados el
2026-07-29 para T1.1 (bloquea la implementación del parser en T1.2, principio
P7 de la constitution: TDD estricto contra fixtures reales antes de escribir
el parser).

Todas las playlists de este directorio son **listas públicas de agregadores
comunitarios**: enumeran URLs de streams (mayormente HLS/IPTV en abierto o
mirrors de radio pública), no credenciales, no contenido privado, ni streams
de pago. `iptv-org` distribuye su índice bajo licencia permisiva (Unlicense /
dominio público — ver `LICENSE` en `iptv-org/iptv`); `kodinerds-iptv` es un
proyecto comunitario alemán con el mismo espíritu de agregación pública.

## `real/` — fixtures committeados (< 5 MB c/u)

| Archivo | Origen | Tamaño real | `#EXTM3U` | Por qué es útil |
|---|---|---|---|---|
| `iptv_org_news.m3u` | https://iptv-org.github.io/iptv/categories/news.m3u | 232 590 bytes | OK | Categoría "news" del catálogo iptv-org: uso diverso y real de `tvg-id`/`tvg-logo`/`group-title` a través de decenas de proveedores distintos, buen caso para parsing de atributos `#EXTINF` heterogéneos. |
| `iptv_org_sports.m3u` | https://iptv-org.github.io/iptv/categories/sports.m3u | 129 390 bytes | OK | Categoría "sports": similar a `news.m3u` pero con nombres de canal más variados (acentos, paréntesis, sufijos de calidad tipo `FHD`/`HD`), útil para robustez de parsing de nombres. |
| `iptv_org_fr.m3u` | https://iptv-org.github.io/iptv/countries/fr.m3u | 62 157 bytes | OK | Playlist por país (Francia): agrupación `group-title` por temática local, canales con acentos en francés en el nombre — caso de encoding real. |
| `iptv_org_us.m3u` | https://iptv-org.github.io/iptv/countries/us.m3u | 352 306 bytes | OK | Playlist por país (EE.UU.), el más grande de los "por país": buen volumen medio para probar rendimiento del parser sin llegar al tamaño de `large/`. |
| `iptv_org_es_samsung.m3u` | https://raw.githubusercontent.com/iptv-org/iptv/master/streams/es_samsung.m3u | 477 bytes | OK | Fixture "streams" (no agregado por categoría/país sino por dispositivo/proveedor concreto — Samsung TV Plus España): playlist minúscula, útil como caso trivial/rápido en tests unitarios y para verificar que el parser no asume un tamaño mínimo. |
| `kodinerds_clean_tv.m3u` | https://raw.githubusercontent.com/jnk22/kodinerds-iptv/master/iptv/clean/clean_tv.m3u | 80 776 bytes | OK | Proyecto comunitario distinto de iptv-org (kodinerds, alemán): dialecto de generación diferente, buena señal de que el parser no está sobreajustado al formato exacto que emite iptv-org. |
| `iprd_all_stations.m3u` | https://iprd-org.github.io/iprd/site_data/all_stations.m3u | 4 872 710 bytes | OK | Catálogo completo de radio de iprd-org (todas las estaciones): es un M3U de **radio**, no de TV — sin `tvg-logo`/`group-title` de vídeo, formato de `#EXTINF` más plano. Es, además, el fixture committeado más grande (~4.87 MB, dentro del límite de ~5 MB para commitear), útil como caso de volumen medio-alto que sí vive en git (a diferencia de `iptv_org_index.m3u`, ver abajo). |

Todos los archivos anteriores fueron verificados manualmente: la primera
línea es exactamente `#EXTM3U` (sin BOM UTF-8 delante, comprobado con `xxd`),
así que ninguno quedó marcado como fixture rota.

### Fuentes muertas (descartadas, no committeadas)

- `https://jmp2.uk/plu-movies.m3u8` → **404** (confirmado el 2026-07-29 con
  `curl -sI`). No se descargó nada; se documenta aquí para que quede
  constancia de que se intentó y por qué no hay archivo correspondiente.

## `large/` — fixtures NO committeadas (gitignored)

- `iptv_org_index.m3u` ← https://iptv-org.github.io/iptv/index.m3u
  (catálogo completo de iptv-org, >50k canales). Vive en
  `packages/protocols/test/fixtures/m3u/large/`, directorio excluido de git
  (`.gitignore`), y se obtiene mediante `dart run tool/fetch_fixtures.dart`
  (script que lee `tool/fixtures_manifest.json` y verifica el SHA-256 tras la
  descarga). Es el fixture del benchmark de T1.5b (RNF-01, 100k canales) y
  **se deja deliberadamente sin congelar en git**: debe reflejar el tamaño
  real del catálogo upstream en el momento del benchmark, no una foto fija
  de julio 2026. Su entrada en el manifest (`iptv_org_index`) tiene el
  `sha256` relleno con el hash de la descarga verificada el 2026-07-29
  (`8c6eac984b7d07f22b80f8410971637b88ecd88ba09f1e8e0277ed3e8400afa8`); el
  script de fetch debe re-verificar contra ese hash o actualizarlo si el
  catálogo upstream cambia entre sincronizaciones — ver el `$comment` de
  `tool/fixtures_manifest.json`.
- `epgshare01_all_sources.xml.gz` — entrada de manifest gestionada por otro
  agente/tarea (T1.3, parser XMLTV), no tocada en esta pasada de T1.1.

## `edge_cases/` — fixtures sintéticos, un patrón por fichero

Reproducen dialectos rotos/no estándar reales, documentados y verificados uno
a uno (P7: "todo bug de importación reportado se convierte primero en un
golden file, y solo después se arregla"). La mayoría vienen de issues reales
de [4gray/iptvnator](https://github.com/4gray/iptvnator) (reproductor IPTV
open source comparable, útil como fuente de dialectos reales de M3U roto sin
necesidad de credenciales de paneles comerciales). Cada fichero trae en su
propia cabecera de comentario el issue/patrón exacto de origen — este README
resume el porqué de cada uno; **dos issues citados en el encargo original no
encajaban con el patrón descrito y no se usaron tal cual** (ver más abajo).

| Archivo | Fuente | Qué cubre |
|---|---|---|
| `extvlcopt_user_agent.m3u` | Uso real documentado de VLC (no un issue concreto, ver nota abajo) | `#EXTVLCOPT` entre `#EXTINF` y la URL para pasar `http-user-agent`/`http-referrer`/`http-origin`. |
| `kodiprop_drm_single_key.m3u` | [iptvnator#656](https://github.com/4gray/iptvnator/issues/656) | `#KODIPROP` para DRM clearkey con una sola clave (`license_key=id:clave`). Ejemplo literal del issue. |
| `kodiprop_drm_multi_key.m3u` | [iptvnator#656](https://github.com/4gray/iptvnator/issues/656) | Variante multi-clave (`license_key={id1:clave1,id2:clave2,...}`); el ejemplo del issue queda truncado, este fixture extiende el patrón que sí se alcanza a ver a 3 claves plausibles — anotado en su cabecera por si hay que reconciliar con el formato exacto más adelante. |
| `pipe_user_agent_referer.m3u` | [iptvnator#57](https://github.com/4gray/iptvnator/issues/57) | Sintaxis Kodi `URL\|User-Agent=...&Referer=...`, con una entrada que solo trae uno de los dos parámetros. Ejemplo literal del issue. |
| `catchup_double_question_mark.m3u` | [iptvnator#579](https://github.com/4gray/iptvnator/issues/579) | URL de stream con `?token=...` combinada con `catchup-source` que también empieza por `?` — el bug real es concatenar mal y producir un `?` doble en vez de `&`. |
| `extbackup_fallback.m3u` | [iptvnator#1107](https://github.com/4gray/iptvnator/issues/1107) | Tag propuesto `#EXTBACKUP` para URLs de fallback por canal. **No es un estándar M3U establecido** — el propio issue lo aclara, es una feature request, no un caso ya soportado por ningún parser real. |
| `pipe_separated_fallback.m3u` | [iptvnator#1107](https://github.com/4gray/iptvnator/issues/1107) | Variante alternativa de la misma propuesta: `URL1\|URL2\|URL3`. Ambigüedad real anotada en la cabecera: a nivel de tokenizer es indistinguible de `pipe_user_agent_referer.m3u` (`URL\|Clave=Valor`) — el parser necesita desambiguar. |
| `unquoted_attributes.m3u` | Dialecto habitual de generadores caseros | Atributos `#EXTINF` sin comillas (`tvg-id=x` en vez de `tvg-id="x"`), frente al estándar de facto con comillas dobles. |
| `encoding_utf8_bom.m3u` | Sintético | Misma playlist base (con acentos españoles reales) en UTF-8 **con BOM** (`EF BB BF`). |
| `encoding_latin1.m3u` | Sintético | Misma playlist base en ISO-8859-1/Latin-1 (sin BOM). |
| `encoding_utf16.m3u` | Sintético | Misma playlist base en UTF-16 con BOM. |
| `encoding_crlf_lf_mixed.m3u` | Sintético | Misma playlist base con finales de línea alternados CRLF/LF línea a línea (UTF-8, sin BOM). |

Los 4 fixtures de `encoding_*` comparten exactamente la misma playlist de 3
canales españoles (La 1, Antena 3, Telecinco — nombres con tildes reales:
"España", "Películas") reexportada en cada encoding, verificados
byte-a-byte (BOM correcto, decode correcto, alternancia CRLF/LF confirmada
línea a línea) antes de guardarlos.

### Correcciones respecto al encargo original

Dos de los seis issues de iptvnator citados originalmente **no contenían el
patrón que se les atribuía**, verificado con `gh issue view` antes de
construir nada a partir de ellos:

- **`#465`** ("Add url playlist with User-Agent") es una petición de UI (un
  campo para introducir el User-Agent al añadir una playlist), no trae
  ningún ejemplo de sintaxis M3U. El patrón `#EXTVLCOPT` que se le atribuía
  se documentó en su lugar como uso real y estándar de VLC (que además
  aparece de forma natural en el propio ejemplo de `#656`).
- **`#1189`** ("Duvida sobre m3u?") es un reporte vago sin snippet
  reproducible: pregunta por qué una playlist de un proyecto de terceros
  (`OwnerPlugins/pluto-tv-m3u`) no funciona, sin mostrar ningún patrón de
  saltos de línea identificable. No se construyó ningún fixture a partir de
  él — el hueco de "saltos de línea inusuales" ya queda cubierto por
  `encoding_crlf_lf_mixed.m3u`.
