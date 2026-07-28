# Tasks — Desglose accionable

> Espejo de `02-Proyectos/Reproductor IPTV Multiplataforma/tasks.md` en el vault. Ver `.specify/README.md` para la regla de sincronización.

## Protocolo de documentación del proyecto (regla operativa — LÉELA)

Reparto de responsabilidades entre herramientas, coherente con la jerarquía de fuentes (vault > Notion > Figma > repo) y con el antipatrón de `AGENTS.md` §9 del vault (no escribir resúmenes de IA fuera de `80-AI-Memoria/`):

- **Notion — progreso tarea a tarea**: al completar cada tarea, Claude Code marca su estado (`Sin empezar → En progreso → Lista`) en la BD *Tareas — IPTV* y escribe una línea de resultado. Una tarea solo pasa a "Lista" si cumple su campo *Hecho cuando*. Aquí vive el estado.
- **Obsidian — solo memoria permanente**, no microprogreso:
  - **Decisión arquitectónica** → nuevo ADR en `ADRs/` (formato MADR).
  - **Conocimiento reutilizable nuevo** → nota en `03-Conocimiento/` (buscar antes de crear).
  - **Cierre de sprint o de sesión** → actualizar `handoff.md` (protocolo 12) + bitácora en el diario / `80-AI-Memoria/` según AGENTS.md §8.
  - Enmienda de `spec`/`plan`/`tasks` si el alcance cambió (SDD vivo).
- **No** se escribe una bitácora por cada tarea en las notas del proyecto: eso es ruido y contamina el vault. El microprogreso es de Notion.

**Esta regla es la que gobierna cómo Claude Code documenta su trabajo en este repo.** Ver también `CLAUDE.md` en la raíz.

## Fase 0 · Setup (1 semana)

- [ ] **T0.1** Crear repo `iptv-player` (privado hasta resolver D2) con estructura del monorepo (§4.1 del plan) y Melos configurado. *Repo real: `IPTVapp` — ver nota en el handoff.*
- [ ] **T0.2** Copiar artefactos SDD a `.specify/` (constitution, spec, ui-spec, plan, tasks) y establecer la regla de sincronización con esta carpeta del vault.
- [ ] **T0.3** Redactar `CLAUDE.md` del repo: reglas de arquitectura (dependencias entre paquetes), convenciones (conventional commits, TDD en `protocols/` y `pairing/`), uso de Graphify como fuente de contexto del codebase, y el **Protocolo de documentación** de arriba (Notion tarea a tarea; Obsidian solo decisiones/conocimiento/handoff).
- [ ] **T0.4** Instalar toolchains: Flutter estable + targets desktop, Android SDK, `flutter-webos` (SDK de `lg-flutter-webos`; activar Dev Mode en la TV LG). *Depende de: T0.1.* **Dividida en Sprint 0**: T0.4a (Flutter + desktop + Android, entra en el DoD del sprint) / T0.4b (flutter-webos + Dev Mode LG, abierta hasta tener cuenta LG Developer y TV a mano — no bloquea, webOS no entra hasta F4).
- [ ] **T0.5** CI GitHub Actions: matrix build (Windows, Linux, Android) + `flutter analyze` + tests. iOS/webOS se añaden en sus fases. *Depende de: T0.1.*
- [ ] **T0.6** **Graphify (obligatorio)** — checklist completo:
  - [ ] `uv tool install graphifyy`
  - [ ] `.gitignore`: añadir `graphify-out/`, `.graphifyignore`, `.claude/skills/graphify/`
  - [ ] Crear `.graphifyignore` (build/, *.g.dart, lockfiles, assets binarios)
  - [ ] `graphify install --project`
  - [ ] `graphify claude install`
  - [ ] `graphify . --obsidian` → primer grafo
  - [ ] Junction `graphify-out/` → `02-Proyectos/Reproductor IPTV Multiplataforma/Graphify/`
  - [ ] Hook de commit para recordar `graphify update .`
- [ ] **T0.7** App esqueleto con los tres shells vacíos (Tv/Mobile/Desktop) y detección de factor de forma; pipeline verde. *Depende de: T0.4, T0.5.*

## Fase 1 · Núcleo + spikes (3–4 semanas)

### Protocolos (TDD estricto, paquetes Dart puros)

- [ ] **T1.1** Recolectar golden files: ≥ 10 listas M3U reales (grandes, con atributos, rotas, encodings raros), ≥ 3 dumps XMLTV (uno .gz grande), respuestas reales de ≥ 2 paneles Xtream. Anonimizados en `packages/protocols/test/fixtures/`. **Requiere aportación del usuario.**
- [ ] **T1.2** Parser M3U en streaming (isolate, lotes): atributos `tvg-*`, `group-title`, `#EXTVLCOPT`, tolerancia con informe de descartes. *Depende de: T1.1.*
- [ ] **T1.3** Parser XMLTV en streaming con gzip y purga por ventana temporal. *Depende de: T1.1.*
- [ ] **T1.4** Cliente Xtream: auth, live/vod/series (+info), categorías, EPG del panel; dialectos y errores no estándar. *Depende de: T1.1.*
- [ ] **T1.5** Esquema drift + migraciones + FTS5 (normalización de acentos) + campos `updated_at`/`deleted_at` en entidades transferibles; benchmark de 100k canales contra RNF-01. *Depende de: T1.2.*
- [ ] **T1.6** Casos de uso de `core`: añadir/refrescar fuente (upsert diferencial), buscar, favoritos, watch-state.
- [ ] **T1.7** `pairing/` núcleo transportable: formato del paquete de configuración (ui-spec §3.2), motor de merge LWW con tombstones, y protocolo de sesión (token efímero → clave de sesión). Testeable sin red (streams en memoria).

### Spikes (time-box: 2 días cada uno) — **S3 (iOS) aplazado a v1.1 por falta de Mac**

- [ ] **S1** Android/Android TV: media3 vía plugin — HLS + TS + MKV, cambio de canal, en Fire TV real.
- [ ] **S2** Desktop: media_kit (libmpv) **y** libVLC — mismos formatos; implicaciones de licencia para el gate D2.
- [ ] **S4** webOS: hello-world `flutter-webos` en TV LG física + reproducción HLS con el pipeline del sistema. **Confirma o activa el plan B de R1.**
- [ ] **S5** Red local multiplataforma: servidor WebSocket embebido + mDNS en Android TV, Fire TV y webOS (permiso Red Local + declaración Bonjour). Salida: matriz de compatibilidad y elección de librería. **Confirma o ajusta ADR-002.**
- [ ] **T1.8** Informe de spikes → actualizar §4.3/§4.5 del plan y, si procede, ADR-003 "Motores de reproducción por plataforma".
- [ ] ~~**S3** iOS: AVPlayer con TS crudo~~ → **aplazado a v1.1** (requiere Mac).

## Fases 2–7 · Épicas

- **F2 Desktop MVP**: pantallas de ui-spec (fuentes, listado, búsqueda, favoritos, EPG, reproductor desktop) + **gate D2 (licencia)** + beta privada.
- **F3 Android + TV + emparejamiento**: shells touch y TV con D-pad completo, rejilla EPG, requisitos leanback, **HU-08 completo** (recibir en TV: QR + código; enviar desde móvil: escáner + código; transferencia LAN), publicación interna en Play/Amazon.
- **F4 webOS**: port, vídeo del sistema, emparejamiento en TvShell webOS, empaquetado IPK, QA de LG.
- **F6 Sync LAN automática (premium)**: claves de dispositivo persistentes, descubrimiento en background, merge automático, pantalla Dispositivos completa (ui-spec §2.12), exportación de configuración a archivo cifrado.
- **F7 Lanzamiento**: i18n (D4), altas en los **5 canales de la v1** (MS Store, Flathub/AUR, Play, Amazon, LG), beta pública, página del producto (D1: nombre).
- **F5 iOS — aplazada a v1.1** (sin Mac): build, player según S3, permiso Red Local, escáner QR, TestFlight, App Store.

## Backlog v2 (no comprometido)

DVR/grabación · timeshift · Samsung Tizen (`flutter-tizen`) · Apple TV · nube opcional opt-in como transporte adicional de sync (ADR-002, opción C) · re-streaming · perfiles multiusuario · control parental.
