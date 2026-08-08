# Servidor Xtream de pruebas (desarrollo)

Servidor Xtream Codes en contenedor, con contenido **enteramente sintético**,
para verificar manualmente lo que "Reproductor desktop" (S6) dejó pendiente:
selector de pistas de audio/subtítulos y seek de VOD/series. M3U nunca
produce ese tipo de contenido, y `MediaKitPlayer` no es testeable en CI
(necesita libmpv nativo) — su verificación es manual por diseño.

**Esto no es, ni simula, ningún proveedor real.** Rulbi es un reproductor
genérico (como VLC/Kodi); este contenedor es solo instrumental de
desarrollo, con contenido de test generado localmente (principio P4).

## Por qué este servidor y no otro

El encargo original citaba `vinikjkkj/xtream-codes-api`. Investigado y
descartado: es un *proxy de republicación* de cuentas trial de IPTV reales
(scrapea un panel con puppeteer y hace `redirect()` al proveedor upstream en
cada ruta de stream — no sirve un solo byte de vídeo propio), sin fichero de
licencia, sin Docker, un único commit (2025-05-19), y su propio README admite
que la lógica ya no funciona.

Se usa en su lugar **[`o0Zz/xtreamcodeserver`](https://github.com/o0Zz/xtreamcodeserver)**
(MIT, Python, paquete PyPI `xtreamcodeserver`). No es una elección nueva:
`packages/protocols/test/fixtures/xtream/README.md` documenta que los
fixtures de T1.1 se capturaron contra el mismo servidor, en
`127.0.0.1:8081` con `test`/`test`.

## Contenido

Generado por `make-fixtures.sh` en build time (nunca comiteado):

| Contenido | Duración | Pistas de audio | Subtítulos | Contenedor |
|---|---|---|---|---|
| 1 canal live | 2 min | 1 (660 Hz) | — | `.ts` |
| 1 película VOD | 10 min | 3 (440/880/220 Hz, eng/spa/fra) | 2 (eng/spa) | `.mp4` (mov_text) |
| Serie, 2 temporadas × 2 episodios | 5 min c/u | 2 (440/880 Hz, eng/spa) | 1 (eng) | `.mkv` (srt) |

Cada vídeo lleva el **timecode transcurrido quemado en la imagen**
(`drawtext=timecode=...`), así que un seek se verifica leyendo la pantalla,
sin depender de lo que reporte el propio reproductor. Cada pista de audio es
un tono senoidal distinto, así que la pista activa se identifica de oído.

**Nota de licencia**: `ffmpeg` es GPL. Se usa aquí únicamente como
herramienta de build para generar fixtures de un contenedor de desarrollo —
no es una dependencia del producto (`packages/*`), así que el principio P8
(sin GPL en el núcleo) no aplica a esta carpeta.

## Uso

```bash
cd tool/xtream-test-server
docker compose -f docker-compose.dev.yml up --build
```

Espera el log `Xtream test server listo — credenciales test/test, puerto 8081`.

### Probar antes de tocar la app

```bash
curl -s "http://127.0.0.1:8081/player_api.php?username=test&password=test" | head -c 400
curl -s "http://127.0.0.1:8081/player_api.php?username=test&password=test&action=get_series_info&series_id=<id>"
curl -sI "http://127.0.0.1:8081/movie/test/test/<vod_id>.mp4"
curl -s -H "Range: bytes=1000000-" -D - -o /dev/null "http://127.0.0.1:8081/movie/test/test/<vod_id>.mp4"
```

La última debe devolver `206 Partial Content` con `content-range`. Los ids
reales de VOD/serie salen de `get_vod_streams`/`get_series` (son
deterministas — CRC32 del nombre normalizado — pero no están fijados a mano
aquí, así que confírmalos con esas dos llamadas antes de construir la URL).

### Apuntar Rulbi

Sin configuración nueva ni nada hardcodeado en la app: pestaña **Fuentes** →
"Nueva fuente" → host `127.0.0.1:8081`, usuario `test`, contraseña `test`.
`normalizeXtreamPanelHost` acepta `http://`, cualquier puerto y `localhost`
sin restricción (ver `packages/protocols/test/xtream/xtream_host_test.dart`).

## Limitaciones conocidas de `xtreamcodeserver` como mock

- `get_vod_info` no puede rellenar los bloques `video`/`audio` al estilo
  ffprobe (limitación documentada por el propio proyecto) — no afecta a la
  reproducción real ni al selector de pistas, que las lee del contenedor.
- `filesystemstream.py` responde `accept-ranges: 0-%d` en vez del valor
  estándar `bytes`. Si un reproductor decidiera que el stream no es
  seekable por esto, es un defecto del servidor de pruebas, no de Rulbi.
- Proyecto pequeño (pocas estrellas), mantenido pero de un solo autor.

## ¿Se queda en el repo?

Sí, a propósito — no es tooling de usar y tirar. Este pendiente existió
porque en S6 no había con qué verificar Xtream real, y las siguientes fases
(Android TV, webOS) van a necesitar volver a verificar exactamente esto. El
coste de mantenerlo es bajo: son ~300 líneas de texto, y el contenido de
vídeo nunca se comitea (se genera en cada `docker build`).
