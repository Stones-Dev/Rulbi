# player_spike — ARCHIVADO (spike de S3 · Spike de escritorio)

**Este directorio es evidencia histórica. El código de dentro no debe reutilizarse.**

## Qué era

El arnés A del spike de S3 · Spike de escritorio: una app Flutter Windows+Linux
(playground de medición, no producción) que reproducía un corpus de canales live y
fixtures VOD sobre `media_kit`/libmpv y exportaba hechos observables a JSON, para
comparar contra libVLC (arnés B, `tool/vlc_probe.dart` en la raíz del repo) y decidir
el motor de reproducción de escritorio del proyecto.

## Cuándo se archivó

**2026-08-01**, en la Fase 0.5.a de la sesión de S4 · Desktop I, tras el consenso de
cierre de S3 (`handoff.md`, entrada "Actualización — 2026-08-01 (consenso de cierre de
S3 · Spike de escritorio)"). El spike ya estaba deliberadamente fuera del array
`workspace:` del `pubspec.yaml` raíz desde su creación (mismo patrón que
`packages/data`, ver `ADR-004`) — archivarlo no quita nada de ese array, sólo mueve el
directorio y retira su workflow de CI del árbol activo.

## Referencias

- Reporte completo del spike, con la matriz de decisión ponderada y la medición real:
  `docs/bench/S3-desktop-spike.md`.
- Decisión formal y corrección de licencia en el vault: **ADR-009** ("Motor de
  reproducción de escritorio - libmpv vía media_kit, y corrección de la licencia
  registrada en el vault").
- `spike-desktop-footprint.yml.archived` en este mismo directorio: el workflow de
  GitHub Actions (`workflow_dispatch` únicamente, nunca gate de `push`/`pull_request`)
  que midió el footprint del bundle Linux. Se conserva con extensión `.archived` para
  que GitHub Actions no lo recoja, pero el `apt-get install libmpv-dev` que contiene
  documenta un hallazgo real (dependencia de *build*, no sólo runtime, en Linux) que
  `ci.yml` necesitará replicar cuando `packages/player` adopte `media_kit` (previsto en
  S6).

## Advertencia

Este código es instrumentación de medición de un solo sprint, sin TDD, sin garantías de
calidad y con su `pubspec.lock` congelado en el estado del spike. **No es el punto de
partida de la implementación real de `PlayerPort`** — esa implementación empieza desde
cero en `packages/player`, ya con la decisión de motor tomada (media_kit sobre libmpv
en modo LGPL).

## Qué contenía (para contexto, no para copiar)

- Arnés A: batch runner sobre `media_kit` (`lib/main.dart`) que reproducía el corpus y
  registraba hechos observables (arranque, buffering, pistas, errores) en JSON.
- Arnés B (fuera de este directorio, sigue en `tool/vlc_probe.dart` en la raíz): mismo
  corpus contra `vlc.exe` en modo CLI — sin binding FFI completo, porque `dart_vlc` está
  descontinuado (pub.dev lo marca *"replaced by: media_kit"*) y no existe binding
  Flutter de escritorio mantenido para libVLC.
