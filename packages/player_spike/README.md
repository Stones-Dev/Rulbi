# player_spike — spike descartable de S3 · Spike de escritorio

**Este paquete no es producción y no forma parte de la arquitectura del proyecto.**
Es un playground de medición para decidir el motor de reproducción de escritorio
(libmpv/`media_kit` vs libVLC) entre Windows y Linux, exigido por el sprint
**S3 · Spike de escritorio** (Notion, Semana 4, gate técnico parcial de F2 · Desktop MVP).

## Por qué está fuera del workspace Melos

Deliberadamente **no** aparece en el array `workspace:` del `pubspec.yaml` raíz — mismo
patrón que `packages/data` ([[ADR-004]] en el vault). Consecuencias:

- `melos bootstrap` / `melos run analyze` / `melos run test` no lo tocan.
- No tiene ningún paso en `.github/workflows/ci.yml`.
- Tiene su propio `pubspec.lock` independiente; se bootstrapea con
  `flutter pub get` ejecutado dentro de `packages/player_spike/`, no desde la raíz.
- Por construcción, nada de lo que se haga aquí puede romper la CI del resto del monorepo.

## Qué contiene

- Arnés A: batch runner sobre `media_kit` (`lib/`) que reproduce un corpus de URLs/ficheros
  y registra hechos observables (arranque, buffering, pistas, errores) en JSON.
- Referencia al arnés B (`tool/vlc_probe.dart`, en la raíz del repo): mismo corpus contra
  `vlc.exe` en modo CLI, para medir libVLC como motor sin construir un binding FFI completo
  (justificación: `dart_vlc` está descontinuado — pub.dev lo marca *"replaced by:
  media_kit"* — no hay binding Flutter de escritorio mantenido que valga la pena envolver).

Los datos y la recomendación firme viven en `docs/bench/S3-desktop-spike.md`
(raíz del repo), no en este README.

## Ciclo de vida

Nace en S3 (2026-07-31/agosto). Al cerrar el sprint, este directorio se archiva completo
en `docs/spikes/player_spike-archive/` como evidencia histórica — no se borra, no se
convierte en el `PlayerPort` real. La implementación de producción vuelve a empezar desde
cero en `packages/player`, ya con la decisión de motor tomada.
