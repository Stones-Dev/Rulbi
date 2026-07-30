# Fixtures XMLTV/EPG (T1.1)

Golden files reales para el parser XMLTV/EPG (bloquea T1.3, principio P7 —
TDD estricto en `packages/protocols/`). Todo bug de importación reportado se
convierte primero en un golden file nuevo aquí, y solo después se arregla el
parser.

## `iptv-org/epg` — ruta estática muerta, no usar

El brief original de esta tarea asumía que las guías pre-generadas de
`iptv-org/epg` seguían publicándose en
`https://iptv-org.github.io/epg/guides/**/*.xml.gz`. **Confirmado muerto el
2026-07-29**: `https://iptv-org.github.io/epg/guides/en/directv.com.xml.gz`
devuelve `404`. El proyecto `iptv-org/epg` dejó de publicar guías
pre-generadas vía GitHub Pages y ahora requiere ejecutar su *grabber* bajo
demanda (no hay archivo estático que descargar).

**No referenciar ni depender del patrón `iptv-org.github.io/epg/guides/**`
en ningún otro sitio de este repo** — está muerto, no es un problema
transitorio. `packages/protocols/test/fixtures/m3u/` sí sigue usando
`iptv-org` para catálogos M3U (ruta distinta, `iptv-org/iptv`, viva); esto
solo afecta a las guías EPG de `iptv-org/epg`.

Se sustituyó por dos fuentes alternativas verificadas vivas el 2026-07-29:
`epg.pw` y `epgshare01.online`. Ambos son servicios públicos de agregación
de EPG que recopilan datos de guías de programación disponibles
públicamente — práctica estándar en el ecosistema de herramientas IPTV. No
requieren credenciales ni acceso a paneles privados.

## Fixtures committeadas

### `epg_pw_lite.xml.gz`

- **Origen**: https://epg.pw/xmltv/epg_lite.xml.gz
- **Tamaño**: ~1.85 MB comprimido (1,849,621 bytes), ~19.2 MB descomprimido.
- **Naturaleza**: EPG pública agregada por `epg.pw` (`FREE EPG`), múltiples
  canales/idiomas (se observan `lang="MY"` entre otros).
- **Verificación**: `gzip -t` OK; descomprime a XML válido con raíz `<tv>`
  cerca del inicio (`generator-info-name="epg.pw"`).
- **Por qué es útil**: fixture EPG "genérica" de tamaño moderado, variedad
  de canales internacionales, buena para cobertura general del parser sin
  ser tan pesada como `epgshare01_es1.xml.gz`.

### `epgshare01_es1.xml.gz`

- **Origen**: https://epgshare01.online/epgshare01/epg_ripper_ES1.xml.gz
- **Tamaño**: ~2.94 MB comprimido (3,083,941 bytes), ~24.1 MB descomprimido.
- **Naturaleza**: EPG real y de tamaño considerable en español, agregada por
  `epgshare01.online` (`epg_ripper`), con `DOCTYPE tv SYSTEM "xmltv.dtd"` y
  canales como `#Vamos`, `324`, etc.
- **Verificación**: `gzip -t` OK; descomprime a XML válido con raíz `<tv>`
  cerca del inicio.
- **Por qué es útil**: EPG real y de tamaño considerable en español —
  cobertura realista de parsing, timezones (`lang="es"`) y codificación de
  caracteres (acentos, ñ) que un fixture sintético no ejercitaría.

Ambos fixtures caben cómodamente bajo el límite de ~5 MB de tamaño de commit
para fixtures de este repo, así que ambos se commitean.

## Fixture grande NO committeada: `epgshare01_all_sources.xml.gz`

- **Origen**: https://epgshare01.online/epgshare01/epg_ripper_ALL_SOURCES1.xml.gz
- **Ubicación**: `packages/protocols/test/fixtures/m3u/large/epgshare01_all_sources.xml.gz`
  (comparte el directorio `m3u/large/` con los fixtures M3U grandes; ese
  directorio está en `.gitignore` — `packages/protocols/test/fixtures/m3u/large/*`).
- **Tamaño real**: ~193 MB (confirmado por `Content-Length` el 2026-07-29;
  la estimación original de "~80 MB" era optimista — ver
  `tool/fixtures_manifest.json`).
- **No se commitea** por tamaño: muy por encima del límite de ~5 MB de
  fixtures del repo. Se descarga bajo demanda con
  `dart run tool/fetch_fixtures.dart`, que la verifica contra el SHA-256
  registrado en `tool/fixtures_manifest.json` (entrada `epgshare01_all_sources`).
- **Por qué existe**: es una prueba de estrés del parser XMLTV en
  streaming/gzip (T1.3) — volumen y throughput, no un caso funcional
  distinto de `epgshare01_es1.xml.gz`. No añade cobertura de dialecto o
  encoding nueva; solo tamaño.

## Verificación aplicada a cada fixture committeada

1. `gzip -t <fixture>` — integridad del contenedor gzip.
2. `gzip -dc <fixture> | head -c 500` — la salida descomprimida empieza con
   `<?xml ...?>` seguido de una raíz `<tv ...>` (no HTML de error, no
   binario truncado).

Si algún fixture fallara esta verificación, se documentaría aquí de forma
visible en vez de incluirse silenciosamente.

## T1.3 (parser XMLTV): sin `edge_cases/` — desviación deliberada respecto a M3U

El plan original de T1.3 preveía un directorio `xmltv/edge_cases/` con un
fichero `.xml` por dialecto, replicando la convención de
`m3u/edge_cases/` (T1.2). Al implementar, se decidió **no** crear ese
directorio — desviación real, documentada aquí en vez de dejarla
implícita:

- Los `edge_cases/*.m3u` de M3U documentan **dialectos rotos reales**,
  casi todos con un issue de GitHub citado como fuente
  (`4gray/iptvnator`). Para XMLTV no se investigó un repositorio
  equivalente de bugs de importación reales — el trabajo de T1.3 se
  centró en las 9 baterías de tests (`packages/protocols/test/xmltv/`),
  cada una cubriendo un aspecto del parser (fechas, núcleo SAX, ventana
  temporal, tolerancia, encoding/gunzip, documentos malformados, isolate,
  fixtures reales, estrés de memoria) contra casos **sintéticos
  minúsculos e inline** en el propio archivo de test — no representan un
  bug reportado citable, son ejercicios dirigidos de una rama concreta
  del estado del parser (p. ej. "`<icon/>` self-closing", "`<title>`
  duplicado").
- Extraer cada uno de esos fragmentos a un fichero `.xml` individual
  habría producido decenas de ficheros de un puñado de líneas cada uno,
  sin el valor documental que sí tienen los `edge_cases/` de M3U (un
  issue real detrás de cada archivo). El coste de la extracción no
  parecía justificar el beneficio frente a dejarlos donde se leen mejor:
  junto a la aserción que verifican.
- Las **2 fixtures reales** de T1.1 (`epg_pw_lite.xml.gz`,
  `epgshare01_es1.xml.gz`, documentadas arriba) sí se usan como archivos,
  en `xmltv_real_fixtures_test.dart` — ahí el patrón de M3U (fixture real
  en disco) se mantiene sin cambios.
- La prueba de estrés (`xmltv_benchmark_test.dart`) sí encontró un
  **dialecto roto real** (no sintético) en producción: `stop` con
  minuto `60` en la fuente `MUSIC.BOX.00s.musicbox` del agregado de
  epgshare01 — ver `docs/bench/T1.3-xmltv-stress.md` para el detalle. Si
  en el futuro se decide construir una batería `edge_cases/` real para
  XMLTV, ese es un candidato con procedencia genuina, a diferencia de los
  fragmentos sintéticos actuales.

Si se retoma este directorio más adelante (p. ej. al escribir T1.9,
"Informe de descartes"), este README es el sitio donde documentar la
decisión de hacerlo o de seguir sin él.
