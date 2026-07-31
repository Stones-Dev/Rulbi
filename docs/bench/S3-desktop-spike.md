# S3 · Spike de escritorio — libmpv (media_kit) vs libVLC

**Tarea**: [Spike S2 · desktop](https://app.notion.com/p/3a3df75619268186bbcfcd57c974a7d5)
(*Tareas — IPTV*, Sprint **S3 · Spike de escritorio**, Semana 4).
**Hecho cuando** (Notion): "Tabla comparativa con formatos, rendimiento y licencias para
el gate D2".
**Consenso de cierre de S3** (Notion): "Gate técnico PARCIAL (sólo escritorio): aprobar
motor de reproducción de escritorio; documentar qué queda pendiente para el gate técnico
completo (S3.5); replanificar F2 con la decisión ya tomada, sin esperar a S3.5."

**Veredicto**: *(pendiente — se rellena en el bloque 7, tras completar las mediciones)*.

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

*(pendiente — bloques 4 y 5)*

---

## C4 — Footprint

*(pendiente — bloque 6)*

---

## Matriz final y recomendación

*(pendiente — bloque 7, solo tras completar todas las mediciones)*

---

## Riesgos residuales anticipados

- Linux no se verifica en runtime este sprint (solo build/footprint en CI) — riesgo
  explícito para S4/S5.
- El brazo libVLC se mide como motor vía CLI, no como plugin Flutter real — si el veredicto
  favoreciera igualmente a libVLC, construir el binding sería un coste adicional no medido
  aquí.

## Referencia de sesión

*(pendiente — commits y run de CI verificado se citan en el bloque 7 de cierre)*
