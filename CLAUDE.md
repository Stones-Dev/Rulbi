# CLAUDE.md — Reproductor IPTV Multiplataforma (repo `IPTVapp`)

Este repo implementa el reproductor IPTV multiplataforma (Flutter/Dart, monorepo Melos). Antes de tocar código, lee **`.specify/`** — es el espejo de los artefactos SDD del vault de Obsidian (constitution, spec, ui-spec, plan, tasks). El vault (`02-Proyectos/Reproductor IPTV Multiplataforma/`) es la fuente de verdad técnica; `.specify/` puede quedarse desactualizado entre sincronizaciones — ver `.specify/README.md`.

**Nota de nombres**: el nombre de trabajo del proyecto es "iptv-player" en el vault, pero el repo real (ya existente en GitHub, `Stones-Dev/IPTVapp`) es `IPTVapp`. El paquete raíz de Dart se llama `iptv_player`. El identificador de aplicación (bundle/application ID, `--org` de `flutter create`) es **`com.stonesdev.iptv`** — permanente, independiente del nombre comercial (D1, aún abierta). El nombre comercial sigue siendo una decisión abierta (D1).

## Jerarquía de fuentes

**Vault (qué/por qué) > Notion (cuándo/estado) > Figma (cómo se ve) > repo+codebase-memory-mcp (código).**

Ante cualquier duda de alcance o de diseño, el vault manda. Este repo y su grafo de código (codebase-memory-mcp) son la capa de implementación, no de decisión.

## Spec-Driven Development — obligatorio

Este proyecto sigue SDD estricto (protocolo 11 de `AGENTS.md` del vault): **prohibido implementar sin pasar por constitution → spec → clarify → plan → tasks**, y cada paso lo valida el usuario. No hagas vibe-coding: si vas a construir algo que no está en `.specify/tasks.md` o en las bases de Notion, para y pregunta antes de escribir código.

## Arquitectura — regla de dependencias

Arquitectura limpia por capas, monorepo Melos:

```
apps/app  →  packages/{player, data, pairing}  →  packages/protocols  →  packages/core
                                                                              ↑
                                                                    (no depende de nada)
```

- **`packages/core`** — dominio puro (entidades, casos de uso, puertos como `PlayerPort`). **No importa Flutter ni ninguna API de plataforma.** Es un paquete Dart puro (`flutter create --template=package`), no un plugin.
- **`packages/protocols`** — parsers M3U/XMLTV y cliente Xtream. Igualmente Dart puro, sin Flutter.
- **`packages/data`** — drift/SQLite, FTS5, repositorios, almacén seguro de credenciales (Keychain/Keystore).
- **`packages/player`** — implementaciones de `PlayerPort` por plataforma (media3, libmpv/libVLC, AVPlayer, webOS). Es el **único** lugar del repo donde se permite importar un SDK de reproducción nativo.
- **`packages/pairing`** — emparejamiento QR/código, canal WebSocket local cifrado, motor de merge LWW. Testeable sin red (streams en memoria).
- **`packages/tokens`** — paquete propio de tokens del lenguaje visual (colores, tipografía Inter, espaciado, estilo de foco).
- **`apps/app`** — la única app Flutter. Contiene los tres shells (`TvShell`, `MobileShell`, `DesktopShell`) y el cableado de Riverpod.

**Principio P6 (constitution)**: el dominio no conoce al reproductor. Si un archivo de `core`, `protocols` o `data` necesita importar algo de `player` o de una API de plataforma, es una señal de que el diseño está mal — para y repiensa el puerto, no lo fuerces.

Antes de tocar un paquete que no conoces bien, consulta el grafo de código (codebase-memory-mcp) en vez de asumir la estructura — ver la sección de más abajo.

## Convenciones

- **Conventional commits** (`feat:`, `fix:`, `chore:`, `build:`, `test:`, `docs:`…), con scope del paquete cuando aplique (`feat(protocols): parser M3U en streaming`).
- **PRs pequeñas por tarea** — una tarea de `tasks.md`/Notion ≈ un commit o PR, no una mezcla de varias.
- **CI verde como condición de merge.** No se hace merge a `main` con el pipeline en rojo.
- **TDD estricto en `packages/protocols/` y `packages/pairing/`** (principio P7): los parsers y el cliente Xtream se desarrollan contra una batería de *golden files* reales (`packages/protocols/test/fixtures/`), incluidos casos rotos y dialectos no estándar. **Todo bug de importación reportado se convierte primero en un golden file, y solo después se arregla.** `pairing/` se testea sin red real (streams/sockets en memoria).
- **Sin dependencias GPL** en el núcleo mientras la decisión de licencia (D2) esté abierta (principio P8): preferir Apache-2.0/MIT/LGPL. Si algún día se adopta un componente GPL (p. ej. libmpv en escritorio), se aísla en `packages/player` y se documenta en un ADR con plan de salida.

## Plugins de sesión

- **`security-guidance`** (oficial de Anthropic, `claude-plugins-official`) —
  **activo**. Tres capas: regex por cada edit (coste cero), revisión LLM del
  diff al cerrar turno, revisión agéntica en `git commit`/`git push`.
  Personalización del proyecto en `.claude/claude-security-guidance.md`
  (threat model, se envía al modelo — **sin secretos reales**) y
  `.claude/security-patterns.yaml` (reglas regex propias).
  Los hallazgos son **asistivos, no bloqueantes**: no sustituyen a SAST/DAST ni
  a revisión humana. Kill switch: `SECURITY_GUIDANCE_DISABLE=1`.
  Ver `03-Conocimiento/Security Guidance (plugin oficial de Anthropic).md`.
- **`code-review`** — evaluado y aprobado, **no instalado todavía**: entra en el
  Sprint 6, cuando el proyecto pase a beta privada y se deje de fusionar a
  `main` sin PR. Ver su nota en `03-Conocimiento/`.

## codebase-memory-mcp — obligatorio (norma 2 del proyecto, ADR-005)

`codebase-memory-mcp` sustituyó a Graphify (ADR-005, 2026-07-28: validado en spike, Graphify no encontraba nodos que codebase-memory-mcp sí resuelve). Mantiene un grafo de conocimiento del codebase consultable por herramientas MCP — no un archivo estático que haya que regenerar a mano: un watcher en segundo plano (`auto_watch`, activo) reindexa solo tras cada cambio, y `auto_index` está activado para repos nuevos.

Antes de tocar un paquete desconocido, consulta el grafo — no lo leas como texto, pregúntale:

- `get_architecture` — capas, boundaries entre paquetes, clusters, hotspots.
- `trace_path` — quién llama/es llamado por una función (`direction: both|inbound|outbound`).
- `search_graph` — por `name_pattern` (regex), `qn_pattern`, o `query` (texto libre con ranking BM25).
- `detect_changes` — símbolos impactados por el diff actual (sin commitear o `--since <ref>`).

**Limitación conocida (ADR-005)**: Dart no tiene Hybrid LSP (tier "Good", ~75-89 %); la resolución de llamadas es textual (tree-sitter), no de tipos — `trace_path` puede atribuir una llamada al archivo en vez de al método exacto. Sigue siendo mejor que la alternativa anterior, pero no asumas precisión de IDE.

`.cbmignore` (raíz del repo) excluye lo mismo que excluía `.graphifyignore`. El artefacto de equipo `.codebase-memory/graph.db.zst` **se comittea a propósito** (ADR-005): un compañero que clona el repo arranca desde ahí en vez de reindexar todo desde cero.

## Protocolo de documentación del proyecto (regla operativa)

Reparto de responsabilidades entre herramientas, coherente con la jerarquía de fuentes de arriba y con el antipatrón de `AGENTS.md` §9 del vault (no escribir resúmenes de IA fuera de `80-AI-Memoria/`):

- **Notion — progreso tarea a tarea.** Al completar cada tarea, marca su estado (`Sin empezar → En progreso → Lista`) en la base *Tareas — IPTV* y escribe una línea de resultado. Una tarea solo pasa a "Lista" si cumple su campo *Hecho cuando*. El estado del proyecto vive en Notion, no en el repo.
- **Obsidian — solo memoria permanente, no microprogreso**:
  - Decisión arquitectónica → nuevo ADR en `ADRs/` (formato MADR).
  - Conocimiento reutilizable nuevo → nota en `03-Conocimiento/` del vault (buscar antes de crear).
  - Cierre de sprint o de sesión → actualizar `handoff.md` del proyecto (protocolo 12).
  - Enmienda de spec/plan/tasks si cambió el alcance (SDD vivo) — se hace primero en el vault, luego se re-sincroniza `.specify/`.
- **No se escribe una bitácora por cada tarea** en este repo ni en las notas del proyecto del vault: eso es ruido. Commits descriptivos + Notion son suficientes para el microprogreso.

## Plataformas de la v1 (recuérdalo al escribir código)

v1 = **Windows, Linux, Android, Android TV/Fire TV, LG webOS** (5 plataformas). **iOS está fuera de la v1** (aplazado a v1.1 por falta de Mac — restricción de recursos, no de producto; ver `.specify/plan.md` revisión 1.2). No añadas el target iOS, dependencias específicas de iOS ni código condicionado a iOS salvo que una tarea de la v1.1 lo pida explícitamente. Esto no afecta al diseño: `PlayerPort` ya deja sitio para añadir iOS después sin tocar `core`/`protocols`/`data`/`pairing`.

## Testing y CI

- `melos run analyze` — `flutter analyze` en todos los paquetes.
- `melos run test` — tests de todos los paquetes.
- CI (GitHub Actions, matrix Windows/Linux/Android) debe estar verde en cada push a `main`. iOS y webOS entran en CI cuando sus fases (F4, v1.1) lo requieran.
- **Los tests con `@Tags(['benchmark'])` SÍ son gate de CI.** `packages/data/dart_test.yaml` solo *declara* el tag `benchmark`, no lo excluye — el CI corre `flutter test` sin `--exclude-tags`, así que corren y bloquean el merge igual que cualquier otro test. `import_100k_benchmark_test.dart` es la única excepción, y no por el tag: se salta vía `markTestSkipped` porque su fixture no está comiteada en el repo. Si algún día ese fixture se comitea, deja de saltarse. No confíes en un comentario que diga "no es gate de CI" sin comprobar `dart_test.yaml` y si el runner pasa `--exclude-tags`.

### Verificación de CI

`gh run watch` devuelve exit 0 aunque el run termine en rojo, salvo que se use `--exit-status`. No declares un run verde solo porque el comando de espera terminó sin error de shell.

Patrón robusto para confirmar un run:

```bash
gh run watch <run-id> --exit-status
gh run view <run-id> --json conclusion -q .conclusion   # debe imprimir literal: success
```

Un run solo está verde si esa segunda línea imprime `success`. `failure`, `cancelled`, `timed_out`, o vacío (aún en curso) no cuentan.

Para triajar un run rojo sin leer el log completo:

```bash
gh run view <run-id> --json jobs -q '.jobs[] | .name as $j | .steps[] | select(.conclusion=="failure") | "\($j) :: \(.name)"'
gh run view --job <job-id> --log-failed
```

Al anotar el resultado en `handoff.md` o Notion, cita el `<run-id>` junto a la conclusión verificada — nunca "CI verde" a secas. Si la sesión se cierra antes de que el run termine, anótalo como pendiente ("debe confirmarse verde"), no como confirmado.

## Verificar antes de firmar: "declararse hecho sin haber hecho"

Dos sprints consecutivos han producido la misma clase de fallo, así que ya no es un
incidente aislado — es un modo de fallo del proceso:

- **Retro de S2, defecto (c)**: la sesión que cerró ADR-007 marcó su tarea de Notion como
  `Lista` cambiando solo el campo `Estado`, sin reescribir el "Hecho cuando" — que se
  quedó con el criterio de aceptación original en vez de la línea de resultado real.
- **Retro de S3, defecto (a)**: `ADR-009` y `plan.md` rev. 1.5 declararon "corregir
  `constitution.md`" (la inversión de licencias GPL/LGPL en P8) sin que el commit de esa
  sesión tocara de hecho el texto de P8. Se detectó en el consenso de cierre, al
  consultar el vault antes de firmar, y se corrigió ahí mismo.

**Regla generalizada**: cualquier declaración de "corrijo / actualizo / cierro X en Y"
obliga a **abrir Y y verificar su texto antes de firmar la sesión**. Crear un ADR, una
revisión de plan, o cambiar el estado de una tarea que *diga* que corrige otro archivo
no corrige ese archivo — solo lo corrige el diff que lo toca.

Checklist operativo antes de firmar cualquier sesión:

- Si escribiste un ADR o una revisión de plan que dice "corrige X": abre X y confirma
  que X está de hecho corregido.
- Si marcaste una tarea de Notion como `Lista`: abre el campo "Hecho cuando" y confirma
  que refleja el trabajo real de esta sesión (patrón de T1.4/T1.5b/T1.6b: se reescribe
  enterito), no que sigue con el criterio de aceptación original.
- Si el handoff dice "actualicé Y": abre Y y confirma.

Los ADRs y las revisiones de plan pueden **hacer referencia** a la corrección de otro
archivo ("esta decisión implica corregir X") — eso es legítimo. Pero entonces el commit
de esa misma sesión también tiene que **tocar X**. Si no lo toca, la referencia es una
promesa, no un hecho, y se anota como pendiente explícito en la siguiente entrada de
`handoff.md`, no se da por resuelta.

## Para el usuario (viene de TypeScript / PHP-Laravel)

Dart es nuevo para ti — algunos paralelismos útiles mientras trabajamos:

| Dart/Flutter | Equivalente TS/Laravel |
|---|---|
| `melos bootstrap` | `pnpm install` en un monorepo de workspaces |
| paquete Dart puro (`core`, `protocols`) | un paquete `npm` sin dependencia de `react`/`vue` |
| `pubspec.yaml` | `package.json` / `composer.json` |
| Riverpod (`Provider`) | un contenedor de DI + estado reactivo (piensa en algo entre un store de Vue/Pinia y la inyección de dependencias de Laravel) |
| `drift` sobre SQLite | Eloquent, pero generando SQL tipado en compilación en vez de en runtime |
| null safety (`String?` vs `String`) | muy parecido al `strict` de TypeScript, pero forzado por el compilador de Dart, no por un linter |
| isolates (para parsing pesado) | el equivalente a un worker thread de Node — memoria aislada, comunicación por mensajes |

Si algo de Dart no tiene un paralelismo claro, dilo explícitamente en vez de asumir que ya lo conoces.
