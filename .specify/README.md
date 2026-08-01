# .specify/ — Espejo de los artefactos SDD

Este directorio es un **espejo de solo lectura** de la carpeta del proyecto en el vault de Obsidian:

```
02-Proyectos/Reproductor IPTV Multiplataforma/
```

## Regla de sincronización

**El vault es la fuente de verdad.** Jerarquía de fuentes del proyecto: **vault (qué/por qué) > Notion (cuándo/estado) > Figma (cómo se ve) > repo+codebase-memory-mcp (código)**.

- Toda enmienda a constitution, spec, ui-spec, plan o tasks se escribe **primero en el vault**, y **después** se re-copia aquí.
- **No edites los archivos de `.specify/` directamente** como si fueran la fuente — se sobrescribirán en la siguiente sincronización y la edición se perderá.
- Claude Code lee estos archivos para tener el contexto SDD disponible sin depender del conector MCP de Obsidian en cada sesión, pero si hay conflicto entre lo que dice aquí y lo que dice el vault, **gana el vault**.

## Contenido

| Archivo | Origen en el vault | Última sincronización |
|---|---|---|
| `constitution.md` | `constitution.md` | 2026-07-28 (Sprint 0) |
| `spec.md` | `spec.md` (rev. 1.1) | 2026-07-28 (Sprint 0) |
| `ui-spec.md` | `ui-spec.md` | 2026-07-28 (Sprint 0) |
| `plan.md` | `plan.md` (rev. 1.5) | 2026-08-01 (S3 · Spike de escritorio, ADR-009) |
| `tasks.md` | `tasks.md` | 2026-07-29 (cierre de migración ADR-005) |

Los ADRs (`ADR-001`–`ADR-009`) **no se copian aquí**: viven solo en el vault (`02-Proyectos/Reproductor IPTV Multiplataforma/ADRs/`), que es su ubicación canónica según el protocolo 11/7 de `AGENTS.md`.

## Cuándo re-sincronizar

Cada vez que el vault registre una revisión de spec/plan/tasks (SDD vivo, protocolo 11 de `AGENTS.md`) o al cierre de un sprint si hubo enmiendas. Se anota en el handoff del proyecto cuándo se hizo la última sincronización.
