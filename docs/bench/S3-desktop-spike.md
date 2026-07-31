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

*(bloque 2, ver más abajo tras el bloque de andamiaje)*

---

## C3 — Estado de los bindings

*(pendiente — bloque 3)*

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
