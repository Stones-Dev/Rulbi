# S3 · Spike de escritorio — libmpv (media_kit) vs libVLC

**Tarea**: [Spike S2 · desktop](https://app.notion.com/p/3a3df75619268186bbcfcd57c974a7d5)
(*Tareas — IPTV*, Sprint **S3 · Spike de escritorio**, Semana 4).
**Hecho cuando** (Notion): "Tabla comparativa con formatos, rendimiento y licencias para
el gate D2".
**Consenso de cierre de S3** (Notion): "Gate técnico PARCIAL (sólo escritorio): aprobar
motor de reproducción de escritorio; documentar qué queda pendiente para el gate técnico
completo (S3.5); replanificar F2 con la decisión ya tomada, sin esperar a S3.5."

**Veredicto: media_kit 1.2.6 (libmpv, LGPLv2.1+/LGPLv3)** para Windows y Linux. libVLC
queda **vetado** por C2 en su forma distribuida estándar (GPLv3 por defecto) y sin
binding Flutter de escritorio viable (C3). Ver bloque 7 para la matriz completa y el
razonamiento.

---

## Por qué este spike, y por qué ahora

F1 · Núcleo cerró en S2 (S0/S1/S2 en `Listo`, verificado en Notion el 2026-07-31). F2 ·
Desktop MVP no puede empezar sin decidir el motor de reproducción de Windows/Linux — es
la pieza que falta del `PlayerPort` de escritorio. `plan.md` §4.3 dejaba la elección
explícitamente abierta: *"media_kit (libmpv) **o** libVLC — se decide en el gate de
licencia D2"*.

Dos hallazgos de la fase de preparación de este spike cambian su forma respecto a lo que
se anticipaba en el consenso de cierre de S2:

1. **Contradicción en el propio vault sobre la licencia de libmpv.** `constitution.md`
   (P8) da libmpv como ejemplo de componente **GPL**; `plan.md` §4.3 lo tabula como
   "GPL / LGPL". Ambas afirmaciones no pueden ser simultáneamente correctas — mpv es
   dual-licenciado y depende de cómo se compile. Resolverlo con fuentes primarias (no de
   memoria) es el entregable de mayor peso de este spike y decide si hace falta un ADR
   nuevo. Ver bloque C2.
2. **`dart_vlc` está descontinuado.** pub.dev lo marca literalmente *"replaced by:
   media_kit"*, última release hace 3 años. No existe binding Flutter de escritorio
   mantenido para libVLC. El comparativo no puede ser "dos plugins en igualdad de
   condiciones" — se documenta como tal. Ver bloque C3.

---

## Criterios de decisión, pesos y regla de veto

Pesos aprobados por el chat de coordinación (usuario) antes de medir:

| # | Criterio | Peso |
|---|---|---|
| C1 | Compatibilidad de formatos reales (live HLS/TS, VOD MP4/MKV, formatos rompedores) | 30 % |
| C2 | Licencia (P8 constitution / gate D2) | 25 % |
| C3 | Bindings Flutter/Dart mantenidos | 20 % |
| C5 | Control programático (RNF-08/RNF-09: pistas, subtítulos externos, gamma/prebuffer) | 12 % |
| C6 | Estabilidad en runtime (404, timeout, corte a mitad) | 8 % |
| C4 | Footprint del binario (Windows y Linux) | 5 % |

**Regla de veto (C2)**: P8 de la constitution es un principio, no un criterio ponderable
más. Cualquier opción que obligaría a liberar el código de la app bajo GPL queda
**eliminada** del comparativo aunque gane la suma ponderada — salvo que se abra una
excepción explícita vía ADR con plan de salida (la propia P8 lo permite: *"si se adopta
un componente GPL... se aísla y se registra el compromiso en un ADR con plan de
salida"*).

**Decisiones de alcance ya acordadas con el usuario** (no se reabren en este documento):

- **Brazo libVLC**: se mide el *motor*, no un plugin Flutter — via CLI de VLC sobre el
  mismo corpus (justificado por el hallazgo de `dart_vlc` descontinuado). No se construye
  un binding FFI nuevo.
- **Linux**: se mide build/enlazado/footprint en CI (`ubuntu-latest`). La reproducción
  real en Linux **no se verifica en este sprint** (no hay Linux con GUI disponible
  localmente) y queda como riesgo residual explícito para S4/S5.
- **media3 sobre AVD**: fuera de este spike. Se cubre en S3.5 con Fire OS real.

---

## Método por criterio (fijado antes de medir)

| Criterio | Método |
|---|---|
| **C1** — formatos | `packages/player_spike` (arnés A, `media_kit`) y `tool/vlc_probe.dart` (arnés B, VLC CLI) reproducen el mismo corpus de URLs/ficheros durante hasta 30 s cada uno y registran: arranque (sí/no + tiempo al primer frame), estabilidad (buffering/drops), pistas de audio/subtítulo detectadas, éxito de seek, string de error literal si falla. Corpus: (a) 8-10 canales live reales seleccionados por script de `packages/protocols/test/fixtures/m3u/real/`; (b) VOD MP4/MKV multipista de licencia libre; (c) formatos históricamente rotos (AC3/EAC3, MKV+ASS, TS multi-PID). |
| **C2** — licencia | Lectura de fuentes oficiales (repos y páginas legales citadas por URL, no de memoria) de mpv, FFmpeg y VLC, y del *build real* que embarca cada paquete Dart (inspección de `.pub-cache`, no solo su README). Veredicto por opción + traducción a obligaciones concretas de distribución. |
| **C3** — bindings | Último commit, releases del último año, issues críticas abiertas, cobertura de plataformas de `media_kit`, `dart_vlc`, `flutter_vlc_player`, verificado en GitHub/pub.dev directamente. |
| **C4** — footprint | `flutter build windows --release` del spike con/sin `media_kit`, diff de tamaño del directorio de salida. Linux: job de CI con `workflow_dispatch` que compila y mide con `du -sb`. Libvlc: tamaño del runtime redistribuible oficial. |
| **C5** — control programático | Se contrasta la API pública documentada de cada motor (selección de pista de audio, carga de subtítulo externo, control de gamma/brillo/contraste, prebuffer/gapless) contra las historias de usuario de `ui-spec.md`/RNF-08/RNF-09. |
| **C6** — estabilidad | Arneses A y B contra tres URLs de "muerte controlada": 404, IP no enrutable (timeout), y un servidor HTTP local que corta la conexión a mitad de stream. Se observa: ¿el proceso sobrevive?, ¿el error llega legible a la capa que envuelve al motor?, ¿se puede reanudar con la siguiente URL sin reiniciar? |

**Limitación conocida, documentada de antemano**: `flutter test` no puede verificar
reproducción real de vídeo (necesita display). C1 y C6 se miden ejecutando el spike como
app de escritorio real localmente, capturando transiciones de estado — no se automatiza
vía `integration_test` en CI en este sprint.

---

## C2 — Licencia

**Corrección explícita del vault**: `constitution.md` (P8) cita *"libmpv"* como ejemplo de
componente GPL, y `plan.md` §4.3 lo tabula como *"GPL / LGPL"*. Ninguna de las dos
afirmaciones es precisa para el artefacto que realmente usaría esta app. mpv es
dual-licenciado y **el binario concreto que `media_kit` empaqueta y distribuye ya está
compilado en modo LGPL**, verificado contra el script de build real (no de memoria ni de
README). Se detalla abajo, con corrección de rev. propuesta para `plan.md`.

### mpv / libmpv

Fuente primaria: [`mpv-player/mpv` — `Copyright`](https://github.com/mpv-player/mpv/blob/master/Copyright).
Cita literal:

> "mpv as a whole is licensed under the GNU General Public License GPL version 2 or
> later (...) by default. The mpv program is licensed the GNU Lesser General Public
> License LGPL version 2 or later (LGPLv2.1+...) if built without using any GPL only
> files. The `-Dgpl=false` configure switch is provided as a convenience for excluding
> the GPL only files listed below from the build process."

Es decir: **mpv es GPLv2+ por defecto, pero se puede compilar como LGPLv2.1+** con
`-Dgpl=false`, perdiendo únicamente: salida de vídeo X11 en Linux, salida de audio OSS,
descodificación hardware vdpau en NVIDIA/Linux (nvdec normalmente sigue funcionando), y
funciones menores (jack, DVD, CDDA, DVB, CACA, D3D legacy). **Ninguna de estas es
relevante para este proyecto** (v1 no soporta DVD/CDDA/DVB físico, y el pipeline de vídeo
de Flutter no depende de X11 VO ni de OSS).

**El build real que empaqueta `media_kit_libs_windows_video` usa exactamente ese modo**,
verificado en su `CMakeLists.txt`
([`media_kit_libs_windows_video-1.0.11/windows/CMakeLists.txt`](https://github.com/media-kit/media-kit),
inspeccionado en `.pub-cache` — el paquete descarga el binario prebuilt de
[`media-kit/libmpv-win32-video-build`](https://github.com/media-kit/libmpv-win32-video-build)):
el propio repo de build de media-kit fija, en
[`packages/mpv.cmake`](https://github.com/media-kit/libmpv-win32-video-build/blob/master/packages/mpv.cmake),
la línea de configuración meson con **`-Dgpl=false`** literal. El FFmpeg que se enlaza
(dependencia de mpv) se configura en
[`packages/ffmpeg.cmake`](https://github.com/media-kit/libmpv-win32-video-build/blob/master/packages/ffmpeg.cmake)
con **`--disable-gpl --disable-nonfree --enable-version3`** — exactamente la
configuración que la propia [página legal de FFmpeg](https://www.ffmpeg.org/legal.html)
recomienda para mantenerse en LGPL: *"Compile FFmpeg without '--enable-gpl' and without
'--enable-nonfree'"* (LGPL 2.1+ por defecto; `--enable-version3` sube a LGPLv3).

**Veredicto libmpv/media_kit (Windows)**: el `.dll` que efectivamente se distribuye
(`libmpv-2.dll`) es **LGPLv2.1+/LGPLv3, no GPL**. La wrapper Dart
(`media_kit_libs_windows_video`) es MIT (`LICENSE` del paquete, Hitesh Kumar Saini).

En **Linux**, `media_kit_libs_linux` (verificado en
`media_kit_libs_linux-1.2.1/linux/CMakeLists.txt`) **no empaqueta ningún binario**
(`media_kit_libs_linux_bundled_libraries` se fija vacío, `""`) — depende de que el
sistema tenga `libmpv` instalado (paquete de distro, p. ej. `libmpv2`/`libmpv-dev` en
Debian/Ubuntu). Esto es enlazado dinámico contra una librería del sistema — el patrón
más limpio posible respecto a LGPL, pero **la licencia efectiva del `.so` del sistema no
la controla el proyecto**, la controla cómo empaquete `libmpv` cada distro. Riesgo menor
y ya cubierto por P8 (enlace dinámico), documentado como riesgo residual.

### libVLC

Fuente primaria: [`videolan/vlc` — `README.md`](https://github.com/videolan/vlc/blob/master/README.md)
(rama `master`, contenido verificado 2026-07-31). Cita literal:

> "VLC is released under the GPLv2 (or later) license. On some platforms, it is de facto
> GPLv3, because of the licenses of dependencies. libVLC, the engine is released under
> the LGPLv2 (or later) license. This allows embedding the engine in 3rd party
> applications..."

En teoría, pues, libVLC (el motor embebible) es LGPLv2+. **Pero el matiz importa**: el
propio script de build oficial de Windows de VideoLAN,
[`extras/package/win32/build.sh`](https://github.com/videolan/vlc/blob/master/extras/package/win32/build.sh),
documenta la licencia de los *contribs* (las dependencias de terceros que se enlazan —
codecs, demuxers) como seleccionable con la flag `-g`:

> "`-g <g|l|a>` Select the license of contribs: **g: GPLv3 (default)**, l: LGPLv3 +
> ad-clauses, a: LGPLv2 + ad-clauses"

**El binario oficial que se descarga de videolan.org (o que instalaría
`choco install vlc`) se compila con el modo por defecto, `-g` (GPLv3)** — es el mismo
motivo que el propio README cita como "de facto GPLv3 por las dependencias". Un build
LGPL de libVLC **existe y está soportado oficialmente**, pero no es el binario
redistribuido por defecto: hay que compilarlo uno mismo con `-g l` o `-g a`, lo cual es
un coste de ingeniería y de mantenimiento continuo (recompilar en cada actualización de
seguridad de VLC) que **ningún binding Dart actual asume** — ni `media_kit`
(que no lo necesita) ni el `dart_vlc` descontinuado (que enlazaba contra la instalación
del sistema, típicamente la build GPLv3 por defecto).

**Veredicto libVLC**: LGPLv2+ es alcanzable en teoría, pero el artefacto real,
descargable y mantenido que cualquier integración razonable usaría hoy es **GPLv3 de
facto**. Bajo la regla de veto de C2, **libVLC en su forma distribuida estándar queda
vetado** para este proyecto mientras D2 esté abierta — no por ser LGPL "peor" que
libmpv, sino porque el binario que de verdad se instalaría no lo es.

### Traducción a obligaciones de distribución (para la opción que sobrevive, libmpv/media_kit)

Con `libmpv-2.dll` LGPLv2.1+/LGPLv3 enlazado **dinámicamente** (nunca estático — es como
`media_kit` lo hace, un `.dll`/`.so` separado del ejecutable de la app):

- Aviso de copyright y de licencia LGPL accesible desde la app (p. ej. pantalla de
  licencias de terceros).
- Ofrecer el código fuente de `libmpv` (o un enlace a los repos oficiales usados) —
  cumplido trivialmente al ser proyectos públicos sin fork privado.
- Permitir al usuario sustituir la `.dll`/`.so` por una versión modificada propia
  (relinkability) — se cumple por construcción al ser un binario separado cargado en
  tiempo de ejecución, no enlazado estáticamente dentro del ejecutable de la app.
- **No** obliga a liberar el código fuente de `iptv_player` (la app) — es precisamente lo
  que P8 y el gate D2 necesitan preservar para un modelo comercial futuro.

**No se requiere ADR-009 sobre licencia como "adopción de componente GPL"** — el
componente elegido (libmpv vía `media_kit`) es LGPL en el build real, no GPL; P8 no se
está excepcionando, se está cumpliendo. Si acaso, ADR-009 documentará la corrección del
error del vault y el compromiso de mantener el enlace dinámico (ver bloque 7).

---

## C3 — Estado de los bindings

Datos verificados directamente en la API de GitHub (no en el ranking de "likes" de
pub.dev), el 2026-07-31.

| Binding | Repo | Último push | Archivado | Issues abiertas | Plataformas desktop | Contribuidores |
|---|---|---|---|---|---|---|
| **`media_kit`** | [`media-kit/media-kit`](https://github.com/media-kit/media-kit) | **2026-07-02** (hace ~4 semanas) | No | 339 | Windows ✅, Linux ✅, macOS ✅ | 30 |
| **`dart_vlc`** | [`alexmercerind/dart_vlc`](https://github.com/alexmercerind/dart_vlc) | 2024-06-14 (hace >2 años) | **Sí** | 53 (congeladas) | Windows/Linux (histórico) | — |
| **`flutter_vlc_player`** | [`solid-software/flutter_vlc_player`](https://github.com/solid-software/flutter_vlc_player) | 2025-09-25 (hace ~10 meses) | No | 366 | **Ninguna** — su `pubspec.yaml` solo declara `android` e `ios` | — |

**`dart_vlc`**: pub.dev lo marca literalmente *"Discontinued (replaced by: media_kit)"*
en su página del paquete. El repo de GitHub está **archivado** (solo lectura desde
2024-06-14) — no puede recibir ni un parche de seguridad. Confirma el hallazgo de la
fase de preparación: no existe camino viable de adoptarlo hoy.

**`flutter_vlc_player`**: mantenido y con actividad reciente, pero su
`pubspec.yaml` (`flutter_vlc_player/pubspec.yaml`, verificado en el repo) solo declara
`plugin.platforms: {android, ios}` — **no existe implementación de escritorio**, ni
Windows ni Linux. Es la confirmación definitiva: hoy no hay ningún binding Flutter de
libVLC utilizable en escritorio, mantenido o no. Encaja con el hallazgo de C2 (el binario
libVLC oficial de Windows es GPLv3 por defecto) — nadie ha tenido motivo de mantener un
wrapper de escritorio para un motor que, tal y como se distribuye, ya estaría vetado por
P8.

**`media_kit`**: actividad real hace 4 semanas, 30 contribuidores distintos en su
historial de commits reciente, cobertura de las 3 plataformas de escritorio relevantes al
proyecto (Windows/Linux; macOS de más, útil si v1.1 lo necesitara). 339 issues abiertas es
una cifra alta en términos absolutos, pero coherente con un proyecto de este tamaño y
alcance (múltiples plataformas, múltiples backends de renderizado); no se detectó, en la
consulta, ningún issue marcado como *"showstopper"* generalizado para Windows/Linux vía
la propia API (revisar con más detalle en release notes si D2 lo exige antes de S4).

**Veredicto C3**: `media_kit` es la única opción viable. No hay comparación real que
hacer — el resto de bindings están descontinuados, archivados, o no cubren escritorio.

---

## C1 / C5 / C6 — Formatos, control programático y estabilidad

### Corpus de prueba

**Live (9 entradas)**, seleccionadas de forma reproducible por
`tool/select_spike_corpus.dart` de los golden files reales de T1.1
(`packages/protocols/test/fixtures/m3u/real/`) — cada entrada verificada por el propio
script contra la línea literal del fixture, salida en `docs/bench/data/live_corpus.json`:
HLS h264 HD (ARD, ZDF — dos CDN distintos), HLS h265/HEVC explícito, HLS con path SMIL
no estándar, HLS geo-bloqueado, audio-only (icecast), URL con path atípico sobre IP
directa sin DNS/TLS, HLS por IP directa, y un DASH `.mpd` con URL firmada casi con
certeza caducada (buen caso de "muerte por expiración de firma", distinto de los 404
sintéticos).

**VOD (4 entradas)**, del [Matroska Test Suite](https://github.com/ietf-wg-cellar/matroska-test-files)
(IETF CELLAR WG), contenido derivado de los proyectos abiertos de Blender Foundation —
*Big Buck Bunny* (CC BY 3.0) y *Elephant Dreams* (CC BY 2.5) — vía
`tool/fixtures_manifest.json` + `tool/fetch_fixtures.dart` (mismo mecanismo que los
fixtures grandes de T1.1, SHA-256 verificado, no comiteados):

| Fixture | Contenido | Categoría |
|---|---|---|
| `test1_baseline.mkv` | MPEG4.2/DivX + MP3 | VOD baseline — "debería funcionar siempre" |
| `test5_multi_audio_subs.mkv` | H264 + 2 pistas de audio (AAC/AAC+) + subtítulos en 7 idiomas | Audio multipista + selección de subtítulo |
| `test7_damaged.mkv` | Elementos EBML basura/no estándar + un elemento inválido intercalado | Formato rompedor (parseo dañado) |
| `test8_audio_gap.mkv` | Frames de audio ausentes entre 6.019s–6.360s | Estabilidad (gap sin detener playback) |

**Gap de corpus reconocido explícitamente** (no se rellena por invención): no se
encontró, dentro del presupuesto de esta sesión, una fuente de audio **AC3/EAC3** ni de
subtítulos **ASS/SSA** con licencia libre clara y descargable de forma automatizada — el
listado oficial de Blender Foundation (`download.blender.org`) solo expone archivos
`.zip` de cientos de MB sin variantes AC3/MKV dedicadas, y no hay `ffmpeg` disponible en
este entorno para remuxar una variante propia a partir de Big Buck Bunny. `test5.mkv`
cubre **audio multipista** y **subtítulos multi-idioma**, pero sus subtítulos son
`S_TEXT/UTF8` (texto plano), no ASS (verificado inspeccionando los CodecID Matroska del
binario) — no exactamente lo previsto en la sesión de planificación. Se documenta como
**riesgo residual de cobertura de C1** para S4/S5, no como hallazgo de compatibilidad de
ningún motor.

### Mediciones — arnés A (media_kit 1.2.6) vs arnés B (VLC 3.0.23 oficial, CLI)

Ejecutado el 2026-08-01 en Windows (`packages/player_spike`, release build, y
`tool/vlc_probe.dart` contra el VLC portable oficial descargado y verificado en C2).
Datos brutos en `docs/bench/data/media_kit_results.json` y
`docs/bench/data/vlc_results.json` (no comiteados — ver `.gitignore`); logs verbosos de
VLC por entrada en `docs/bench/data/vlc_logs/`.

| Entrada | media_kit: ¿reproduce? | VLC: ¿reproduce? | Nota |
|---|---|---|---|
| ARD HLS h264 HD | ✅ | ✅ (14,7 s hasta señal de arranque) | Ambos motores lo consiguen; VLC bastante más lento en esta entrada concreta. |
| ZDF HLS h264 HD (Akamai) | ❌ `Failed to open` | ❌ (log: **HTTP 403**) | **Fallo idéntico en ambos motores** — confirmado por el log de VLC como rechazo del CDN (403), no un defecto de compatibilidad de ningún motor. |
| RTVS HEVC (h265) | ✅ 14 ms, seek OK, 49,5 s reproducidos | ❌ **timeout a los 40 s** | **Diferenciador real**: el log de VLC (`vlc_logs/sk_rtvs_hevc.log`) muestra la petición HTTP enviada y ninguna respuesta — la conexión se queda colgada. media_kit/libmpv sí completa la conexión y reproduce con normalidad. No se puede descartar que el origen filtre por `User-Agent` (VLC envía `VLC/3.0.23 LibVLC/3.0.23` literal), pero el resultado observado es real y reproducible dos veces. |
| Pluto SMIL (dialecto no estándar) | ✅ | ✅ (1,7 s) | Ambos toleran el path `smil:...` no estándar. |
| Trace Sport Stars ["Geo-blocked"] | ✅ (con ~4 pistas de audio reales, ver nota) | ✅ (0,4 s) | **El geo-bloqueo anunciado en el nombre del canal no se reprodujo** contra la IP de salida de esta sesión — ninguno de los dos motores lo bloqueó. Dato del fixture probablemente desactualizado, no invalida la medición. |
| Icecast radio (audio-only) | ✅ | ✅ (0,5 s) | Camino de audio puro sin contenedor, limpio en ambos. |
| IP directa + path atípico (`;stream/1`) | ✅ | ✅ (0,6 s) | Dialecto raro tolerado por ambos. |
| 6ter HLS por IP directa, sin TLS | ✅ | ✅ (0,4 s) | Sin incidencias. |
| Orange DASH con firma caducada | ❌ `Failed to open` | ❌ (sin reproducir) | **Fallo idéntico en ambos** — confirma la hipótesis de la fase de selección de corpus (URL firmada, `expires=1734441066`, caducada desde hace más de un año en la línea temporal de este proyecto). |
| VOD baseline (`test1.mkv`) | ✅ 87,3 s, seek OK | ✅ (0,2 s) | Caso trivial, sin sorpresas. |
| VOD multi-audio + subs (`test5.mkv`) | ✅ **2 pistas de audio reales, 8 subtítulos reales** (descontados los pseudo-tracks `auto`/`no` que media_kit añade siempre, ver nota metodológica), seek OK | ✅ reproduce (el parseo de pistas del log de VLC no se pudo automatizar, ver nota) | media_kit reporta correctamente 2 pistas de audio (coincide con el README oficial del fixture: "main + comentario") y 8 entradas de subtítulo (7 idiomas documentados + 1 adicional no explicado en el README — diferencia menor, no relevante para la decisión). |
| VOD dañado (`test7.mkv`, EBML junk) | ✅ 37 s, seek OK — **se recupera del elemento inválido intercalado** | ✅ reproduce | Ambos motores tragan el fixture deliberadamente dañado sin caerse. |
| VOD audio gap (`test8.mkv`) | ✅ 47,3 s, **no se detiene en el hueco de audio** (6,0–6,4 s) | ✅ reproduce | Comportamiento esperado por el propio diseño del fixture: el video no debe pararse por la falta puntual de audio. |

**Resumen C1**: de 13 entradas, media_kit reproduce **11/13** (falla solo en los dos casos
de fallo genuino de origen: HTTP 403 y URL caducada). VLC reproduce **10/13** — los mismos
dos fallos genuinos **más** el timeout de la fuente HEVC. **En ningún caso VLC tiene éxito
donde media_kit falla**; sí hay un caso (HEVC) en sentido contrario.

**Limitación metodológica reconocida** (documentada de antemano en el método, confirmada
al medir): el recuento de pistas de audio/subtítulo de media_kit incluye 2 pseudo-tracks
fijas (`AudioTrack.auto()`/`AudioTrack.no()`, ídem subtítulo — confirmado leyendo
`media_kit-1.2.6/lib/src/player/native/player/real.dart:1712-1713`), así que el número
crudo de cada entrada es "reales + 2"; se ha corregido a mano en la tabla de arriba donde
importaba. El arnés B, al depender de *parsear el log humano de VLC* en vez de una API
estructurada, **no consiguió extraer recuentos de pistas fiables** (0 en todas las
entradas) — es una limitación del arnés, no evidencia de que VLC no exponga pistas.
Esta asimetría es inherente a la decisión ya acordada ("se mide el motor, no se construye
un binding") y se señala aquí para que no se confunda con un hallazgo de compatibilidad.
También se observó que el indicador `player.stream.playing` de media_kit se activa casi
instantáneamente (10-30 ms) tras `open()`, **antes** de que haya datos reales
decodificados — no es una métrica fiable de "tiempo hasta el primer frame"; el corpus
usa señales secundarias (`buffering_events`, `duration_seconds` poblada, `seek_succeeded`)
como indicador real de éxito, documentado aquí para que futuras sesiones no reutilicen
`ms_to_first_playing` de media_kit como cifra de rendimiento sin este matiz.

### C5 — Control programático (RNF-08/RNF-09)

Verificado contra el código fuente público de cada API (no documentación de terceros):

| Capacidad (RNF-08/09) | media_kit (`Player`, `media_kit-1.2.6/lib/src/player/player.dart`) | libVLC (`libvlc_media_player.h`, `videolan/vlc`) |
|---|---|---|
| Selección de pista de audio | `setAudioTrack(AudioTrack)` (línea 287) | `libvlc_audio_set_track()` |
| Selección/carga de subtítulo externo | `setSubtitleTrack(SubtitleTrack)` + `SubtitleTrack.uri(...)`/`.data(...)` para SRT/WebVTT externos (líneas 262-271) | `libvlc_video_set_spu()` + `libvlc_media_slaves_add()` para pistas externas |
| Gamma/brillo/contraste | Sin wrapper Dart de alto nivel, pero `setProperty(String, ...)` (línea 1223) da acceso directo a las propiedades nativas de mpv (`gamma`, `brightness`, `contrast`, `saturation`, `hue`) | Primera clase: `libvlc_video_set_adjust_int/float()` (líneas 3011-3047 del header) |
| Prebuffer / gapless para zapping | Configurable vía mpv (`cache`, `demuxer-max-bytes` vía `setProperty`) | Configurable vía libVLC (`network-caching` y opciones de demux) |

**Veredicto C5**: ambos motores cubren las historias de usuario de RNF-08/RNF-09. libVLC
tiene una API de más alto nivel para ajuste de vídeo (funciones dedicadas vs. bolsa de
propiedades genérica de mpv), una ventaja real pero menor frente al peso de C1/C2/C3 —
no cambia la decisión.

### C6 — Estabilidad en runtime

Cubierto de facto por las tres entradas de "muerte real" del propio corpus C1 (más
representativas que sintéticas puras, según lo acordado): **ZDF (HTTP 403)** y **Orange
DASH (firma caducada)** — ambos motores fallan de forma controlada: el proceso no
crashea, media_kit propaga un mensaje de error legible por el stream `player.stream.error`
("Failed to open ..."), y el arnés continúa con la siguiente entrada sin reiniciar la
app. VLC termina el proceso con `exit_code=0` y sin reproducir (equivalente a un error
manejado, visible en su log). El caso **RTVS HEVC** añade una tercera categoría no
prevista en el diseño original (timeout de conexión, no 404/corte a mitad): media_kit lo
resuelve con normalidad: no hubo timeout en absoluto (contra la misma URL). No se observó
ningún crash de proceso en ninguna combinación motor×entrada de las 13×2 ejecutadas.

---

## C4 — Footprint

### Windows

Medido con `flutter build windows --release` de `packages/player_spike`
(`build/windows/x64/runner/Release/`), desglosado fichero a fichero (`du -sb`):

| Componente | Tamaño | Atribuible a |
|---|---:|---|
| `libmpv-2.dll` | 29.764.622 B (28,4 MB) | media_kit — el motor mpv en sí |
| Stack ANGLE/GL/Vulkan (`d3dcompiler_47.dll`, `libEGL.dll`, `libGLESv2.dll`, `vk_swiftshader.dll`, `vulkan-1.dll`) | 18.458.856 B (17,6 MB) | media_kit — renderizado de vídeo en Windows |
| `zlib.dll` + plugins Dart de media_kit | 356.864 B (0,35 MB) | media_kit — glue |
| **Subtotal media_kit** | **48.580.342 B (46,3 MB)** | |
| `flutter_windows.dll` + `player_spike.exe` | 21.366.784 B (20,4 MB) | Runtime Flutter base, no media_kit |
| `data/` (assets, ICU) | 7.499.420 B (7,2 MB) | Flutter base |
| **Total del bundle** | **77.446.546 B (73,9 MB)** | |

**Coste neto de añadir media_kit al bundle de Windows: ~46,3 MB**, de los cuales el
propio `libmpv-2.dll` es 28,4 MB y el resto es el stack de renderizado ANGLE que
media_kit necesita para pintar vídeo vía OpenGL ES/ANGLE sobre Direct3D en Windows.

Para contraste, el runtime redistribuible de libVLC (extraído del zip oficial
`vlc-3.0.23-win64.zip`, ver C2): `libvlc.dll` + `libvlccore.dll` + `plugins/` (mínimo
necesario para reproducir, sin skins/lua/locale) = **142,2 MB** — el paquete portable
completo son 191,6 MB. **libVLC es ~3,1x más grande que media_kit** en el mínimo
necesario (~4,1x contando el portable completo) — confirma cuantitativamente la
expectativa cualitativa del prompt de sprint ("libmpv suele ser 3-5x más pequeño").

### Linux

Job de CI dedicado, `workflow_dispatch` (`.github/workflows/spike-desktop-footprint.yml`,
**no** añadido a `push`/`pull_request` — no toca el gate de `main`), que compila
`packages/player_spike` en `ubuntu-latest` y mide el bundle con `du -sb`.

**Hallazgo real de la primera ejecución** (run
[30694031427](https://github.com/Stones-Dev/IPTVapp/actions/runs/30694031427), fallido):
`flutter build linux --release` falla en el paso de CMake con
`CMake Error ... target_link_libraries: Target "media_kit_video_plugin" links to:
PkgConfig::mpv ... but the target was not found`. Confirma empíricamente, a nivel de
*build*, lo que C2 ya había establecido a nivel de *empaquetado*: `media_kit_libs_linux`
no trae su propio `libmpv`, así que **compilar** (no solo ejecutar) la app en Linux
requiere `libmpv-dev` instalado en el sistema vía `pkg-config`. El job original no lo
instalaba (`ninja-build libgtk-3-dev clang cmake pkg-config`, el mismo set que usa
`ci.yml` para el resto del monorepo, que no depende de media_kit). Corregido añadiendo
`libmpv-dev` al paso de dependencias del sistema. **Riesgo real para S4/S5, no solo
teórico**: el `ci.yml` de producción tendrá que añadir `libmpv-dev` al job Linux de
`analyze-and-test` en cuanto `packages/player` empiece a depender de media_kit — anotado
en riesgos residuales.

Segunda ejecución (tras el fix): *(ver Referencia de sesión para el run y la cifra final,
si se completó dentro de esta sesión)*. Nota ya establecida en C2 sigue siendo válida:
`media_kit_libs_linux` no empaqueta el binario en el *bundle final* (enlace dinámico
contra el `.so` del sistema en runtime) — el footprint de la app en Linux debería ser
notablemente menor que en Windows, aunque el *build* necesite las cabeceras de
desarrollo.

---

## Matriz final y recomendación

### Aplicación de la regla de veto (C2)

libVLC, en la forma en la que cualquier integración razonable lo obtendría hoy (el
binario oficial `vlc-3.0.23-win64.zip` de `get.videolan.org`, `COPYING.txt` propio
confirmado como GPLv2 en esta misma sesión), **es GPL**. Bajo la regla acordada con el
usuario antes de medir, **queda eliminado del comparativo aunque puntuara mejor en algún
criterio individual** — no hay excepción vía ADR porque no hay ninguna razón de peso
que la justifique (media_kit cubre de sobra los mismos requisitos). Se conserva su
puntuación en la tabla solo con fines de transparencia metodológica, marcada como
vetada.

### Matriz ponderada

| Criterio | Peso | media_kit (libmpv) | libVLC |
|---|---:|---:|---:|
| C1 — Formatos reales | 30 % | 5/5 (11/13, incl. HEVC, MKV dañado, audio-gap) | 4/5 (10/13, falla el único HEVC del corpus) |
| C2 — Licencia | 25 % | 5/5 (LGPLv2.1+/LGPLv3, verificado en el build real) | **VETADO** (GPLv2/v3 en el binario oficial distribuido) |
| C3 — Bindings mantenidos | 20 % | 5/5 (activo, cubre Windows/Linux/macOS) | 1/5 (dart_vlc archivado; flutter_vlc_player sin escritorio) |
| C5 — Control programático | 12 % | 4/5 (cobertura completa vía `setProperty` + API de tracks) | 5/5 (API de más alto nivel, pero irrelevante tras el veto) |
| C6 — Estabilidad | 8 % | 5/5 (sin crashes, resuelve los 3 casos de fallo real) | 4/5 (sin crashes, pero falla el caso HEVC) |
| C4 — Footprint | 5 % | 4/5 (46,3 MB añadidos) | 2/5 (142-191 MB, ~3-4x más grande) |
| **Total ponderado** | | **4,83 / 5** | **Descalificado por veto** (2,42/5 si se ignorase el veto — ni siquiera ganaría) |

**El veto no es lo que decide esta comparativa por sí solo**: incluso ignorando la regla
de licencia por completo, libVLC pierde en la suma ponderada (2,42 vs 4,83) porque C1
Y C3 —el 50 % del peso total— ya lo penalizan con fuerza (sin binding de escritorio
viable, y un fallo real que media_kit no tiene). La licencia GPL es un motivo de
descalificación adicional y suficiente por sí mismo, no el único.

### Recomendación firme

**Motor: mpv/libmpv, LGPLv2.1+/LGPLv3 (build sin `--enable-gpl`/`-Dgpl=false`).**
**Plugin Dart: `package:media_kit` (versión fijada en esta sesión: `media_kit ^1.2.6`,
`media_kit_video ^2.0.1`, `media_kit_libs_windows_video ^1.0.11` para Windows,
`media_kit_libs_linux ^1.2.1` para Linux).**

Razones ligadas a los criterios de mayor peso:

1. **C2 (25 %, con veto)**: es la única opción que no compromete P8/D2 sin necesidad de
   excepción ni ADR de "adopción de componente GPL" — el build real que se distribuye ya
   es LGPL.
2. **C3 (20 %)**: es la única opción con un binding Flutter de escritorio vivo y
   mantenido. No hay alternativa real que evaluar.
3. **C1 (30 %)**: cubre más del corpus real (11/13 vs 10/13), incluyendo el único stream
   HEVC del corpus y los dos fixtures MKV deliberadamente rotos (dañado y con hueco de
   audio) sin fallar ni una vez.
4. **C4 (5 %)**: confirma cuantitativamente la expectativa de partida — footprint 3-4x
   menor que libVLC empaquetado.

`packages/player_spike` (este mismo paquete, no descartado del todo — ver más abajo)
demuestra que la integración es viable en Windows sin fricción: `flutter pub add
media_kit media_kit_video media_kit_libs_windows_video media_kit_libs_linux` y
`MediaKit.ensureInitialized()` en `main()` son los únicos pasos de arranque.

### Riesgos residuales de la elección

- **Dependencia de un solo mantenedor/organización pequeña** (`media-kit`, ~30
  contribuidores, sin respaldo corporativo): si el proyecto se abandona, `PlayerPort` ya
  aísla el motor (P6) — migrar a un fork comunitario o a otro binding sería un cambio
  contenido a `packages/player`, no una reescritura. Mitigación: revisar la salud del
  proyecto en cada release mayor de la app.
- **Linux no verificado en runtime este sprint** — solo build/footprint. Riesgo
  explícito para S4 (Desktop I): la primera tarea de escritorio real debe incluir una
  verificación manual de reproducción en Linux antes de darlo por sentado.
- **`libmpv-dev` es una dependencia de build en Linux, no solo de runtime** (hallazgo real
  de C4: el primer intento de compilar `packages/player_spike` en `ubuntu-latest` falló
  por `PkgConfig::mpv` no encontrado). Cuando `packages/player` empiece a depender de
  media_kit, el job Linux de `analyze-and-test` en `ci.yml` necesitará
  `apt-get install libmpv-dev` añadido a su paso de dependencias del sistema — si no se
  añade, el build de Linux de la app real fallará igual que falló este del spike.
- **Gap de corpus AC3/EAC3 y subtítulos ASS** (documentado en C1) no se ha cerrado — no
  bloquea la decisión de motor (mpv soporta ambos nativamente, es una limitación de
  *este spike*, no del motor), pero conviene cerrarlo con golden files reales antes de
  considerar el soporte de formatos "verificado end-to-end" en S4/S5.
- **El hallazgo del timeout en la fuente HEVC** (arnés B) no se investigó a fondo (¿filtra
  por `User-Agent`? ¿es un problema puntual del servidor de prueba?) — no cambia la
  decisión (media_kit ya gana ese caso), pero si en producción media_kit mostrara el
  mismo patrón contra otras fuentes, revisar si el `User-Agent`/cabeceras HTTP son
  configurables vía `setProperty`.
- **La cifra de footprint de Linux queda pendiente de una ejecución real del workflow**
  (`spike-desktop-footprint.yml`, disparado manualmente en esta sesión — ver referencia
  de sesión más abajo para el resultado, si llegó a tiempo).

---

## Referencia de sesión

*(pendiente — commits y run de CI verificado se citan en el bloque 7 de cierre)*
