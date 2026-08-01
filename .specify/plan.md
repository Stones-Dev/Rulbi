# Plan de desarrollo — Reproductor IPTV Multiplataforma

> Espejo de `02-Proyectos/Reproductor IPTV Multiplataforma/plan.md` (rev. 1.5) en el vault. Ver `.specify/README.md` para la regla de sincronización.

> Revisión 1.1 (2026-07-20): sincronización rediseñada como **serverless** por decisión del usuario (ADR-002). Desaparece el backend de v1.

## 1. Resumen ejecutivo
Se propone construir el reproductor IPTV con **Flutter/Dart como base de código única** para Windows, Linux, Android, iOS, Android TV/Fire TV y LG webOS, con arquitectura limpia local-first sobre SQLite, reproducción delegada en motores nativos por plataforma tras una abstracción, y **sincronización sin servidores**: emparejamiento por QR/código de 6 dígitos y transferencia + sync automática por red local. La ventana de oportunidad es real: LG publicó oficialmente el SDK `flutter-webos` y Samsung mantiene `flutter-tizen`, lo que convierte a Flutter en el único stack que hoy alcanza *todas* las plataformas objetivo con un solo equipo — camino vetado para open-tv (Tauri + mpv externo).

Ejecución por 7 fases (F0–F7) con un *gate* de decisión (licencia en F2), metodología SDD, Claude Code con **codebase-memory-mcp obligatorio** (ADR-005) y memoria del proyecto en este vault. Coste de infraestructura: **cero**.

## 2. Estado del arte y oportunidad

| Producto | Stack | Desktop | Móvil | Android TV | webOS | Sync | Debilidad clave |
|---|---|---|---|---|---|---|---|
| open-tv / Fred TV | Tauri (Rust) + Angular + mpv externo | ✅ | Android/iOS (builds aparte) | Parcial | ❌ | ❌ | mpv como dependencia externa; sin TVs web |
| TiviMate | Android nativo | ❌ | Android | ✅ (excelente) | ❌ | Parcial (premium) | Solo ecosistema Android |
| IPTVnator | Electron/Angular | ✅ | ❌ | ❌ | ❌ | ❌ | Electron pesado; sin TV |
| Kodi + PVR | C++ | ✅ | ✅ | ✅ | ❌ | ❌ | Complejidad de configuración enorme |
| **Este proyecto** | Flutter | ✅ | ✅ | ✅ | ✅ | ✅ LAN sin cuentas | — (riesgos en §8) |

Ninguna alternativa cubre a la vez escritorio, móvil y ambos ecosistemas de TV; y ninguna resuelve el onboarding de TV con emparejamiento QR/código al estilo de las grandes plataformas. El nicho "TiviMate-quality en todas partes, con privacidad total" está vacío.

## 3. Stack tecnológico
Decisiones formales en ADR-001 y ADR-002.

| Capa | Elección | Licencia | Nota |
|---|---|---|---|
| Lenguaje / framework | Dart + Flutter estable | BSD-3 | Único stack con cobertura total (incl. `flutter-webos`) |
| Estado / DI | Riverpod | MIT | Testeable, sin magia |
| Base de datos local | SQLite vía drift + **FTS5** | MIT | Búsqueda instantánea; mismo esquema en todas las plataformas |
| HTTP | dio | MIT | Interceptores, cancelación, streaming |
| Reproducción | Abstracción `PlayerPort` + motor por plataforma (§4.3) | — | Principio P6 |
| QR | `qr_flutter` (generar) + `mobile_scanner` (escanear, solo móvil) | MIT/BSD | HU-08 |
| Red local | mDNS/NSD (`bonsoir` o equivalente) + WebSocket local embebido | MIT | HU-08/09; validar por plataforma en spike S5 |
| Monorepo | Melos (paquetes Dart) | MIT | `core`, `protocols`, `data`, `player`, `pairing` |
| CI/CD | GitHub Actions (matrix por plataforma) | — | Builds firmadas + tests en cada push |
| Tooling IA | Claude Code + codebase-memory-mcp + Spec Kit | — | §6, ADR-005 |

**Nota sobre Dart**: no está hoy en tu stack (TS/PHP); la curva desde TypeScript es corta y Claude Code reduce el coste de adopción (riesgo R6).

## 4. Arquitectura técnica

### 4.1 Estructura del monorepo
```
iptv-player/
├── .specify/                  # Artefactos SDD (espejo de esta carpeta del vault)
├── CLAUDE.md                  # Instrucciones del repo para Claude Code
├── .codebase-memory/          # Artefacto de equipo del grafo de código (comiteado, ver ADR-005)
├── .cbmignore                 # Exclusiones del indexado de codebase-memory-mcp
├── melos.yaml
├── packages/
│   ├── core/                  # Dominio puro: entidades, casos de uso, puertos. Sin Flutter.
│   ├── protocols/             # Parsers M3U y XMLTV (streaming) + cliente Xtream. Sin Flutter.
│   ├── data/                  # drift/SQLite, FTS5, repositorios, almacén seguro de credenciales
│   ├── player/                # PlayerPort + implementaciones por plataforma
│   └── pairing/                # Emparejamiento QR/código, canal local cifrado, motor de sync LWW
├── apps/
│   └── app/                   # App Flutter única; targets: windows, linux, android, ios, webos
```

Regla de dependencias (arquitectura limpia): `app → player/data/pairing → protocols → core`. `core` no depende de nada; nada del dominio importa Flutter ni APIs de plataforma.

### 4.2 Modelo de datos (SQLite, idéntico en todas las plataformas)

- `sources` (id, tipo m3u_file|m3u_url|xtream, config, enabled, last_refresh, updated_at, deleted_at)
- `categories` (source_id, tipo live|vod|series, nombre, orden)
- `channels` (source_id, category_id, tipo, nombre, url, tvg_id, logo, metadatos) + índice **FTS5** con normalización de acentos
- `epg_programmes` (tvg_id, start, stop, título, descripción) — solo ventana temporal útil, purga automática
- `favorites` (channel_ref, orden, updated_at, deleted_at)
- `watch_state` (channel_ref, posición, duración, updated_at)
- `paired_devices` (device_id, nombre, plataforma, clave pública, last_seen, auto_sync)

Todas las entidades transferibles llevan `updated_at`/`deleted_at` (tombstones): el mismo modelo sirve para la transferencia inicial y para el merge LWW de la sync LAN. La importación escribe por lotes en transacción, en un isolate, con progreso; el refresco de una fuente es un *upsert* diferencial que preserva favoritos y progreso.

### 4.3 Estrategia de reproducción por plataforma

| Plataforma | Motor propuesto | Licencia | Formatos críticos |
|---|---|---|---|
| Android / Android TV / Fire TV | **media3 (ExoPlayer)** vía plugin | Apache-2.0 | HLS ✅, MPEG-TS ✅, MP4/MKV ✅ |
| iOS | AVPlayer nativo; *fallback* VLCKit si los TS crudos fallan | — / LGPL-2.1 | HLS ✅ nativo; TS ⚠️ (spike v1.1) |
| **Windows / Linux** | **media_kit (libmpv)** — decidido en S3 · Spike de escritorio, ADR-009 | **LGPLv2.1+/LGPLv3** (verificado contra el build real que empaqueta `media_kit_libs_windows_video`/`_linux`, no GPL como se afirmaba antes en esta tabla y en `constitution.md` P8) | HLS ✅, MPEG-TS ✅, MP4/MKV ✅, HEVC ✅ — 11/13 del corpus real del spike, ver `docs/bench/S3-desktop-spike.md` |
| LG webOS | Pipeline multimedia del sistema vía plugins `flutter-webos` | — | Spike S3.5 obligatorio |

**Corrección (2026-08-01, S3 · Spike de escritorio)**: esta tabla afirmaba antes
"GPL / LGPL" para el motor de escritorio, sin resolver cuál. El spike de S3 confirmó
contra fuentes primarias (repos de build de mpv/FFmpeg/media-kit, no documentación de
terceros) que el binario `libmpv` que `media_kit` distribuye para Windows/Linux se
compila explícitamente en modo LGPL (`-Dgpl=false` + `--disable-gpl --disable-nonfree`).
libVLC, en cambio, se distribuye oficialmente en modo GPL por defecto — queda descartado.
Detalle completo, matriz ponderada y riesgos residuales en
`docs/bench/S3-desktop-spike.md` y ADR-009.

### 4.4 Capa de presentación

Tres shells sobre los mismos view-models (Riverpod): `TvShell` (10-foot, D-pad, foco visible), `MobileShell` (touch) y `DesktopShell` (atajos). Detección por plataforma + factor de forma (Android TV por *leanback feature*). Inventario completo de pantallas, campos y estados: **ui-spec**.

### 4.5 Transferencia y sincronización sin servidor (ADR-002)

- **Emparejamiento**: el receptor (típicamente la TV) muestra un QR y un código de 6 dígitos. El QR contiene `{host, port, token efímero}` — nunca credenciales — y no depende de mDNS. El código es la vía sin cámara: mDNS (`_iptvpair._tcp`) localiza al receptor y el código autentica el canal. Último recurso: IP manual.
- **Canal local**: WebSocket embebido en el receptor, cifrado con clave de sesión derivada del token/código. Por él viaja el paquete de configuración (fuentes con secretos, favoritos, progreso, ajustes — el usuario elige qué).
- **Sync automática (premium)**: dispositivos ya emparejados intercambian claves de dispositivo; al coincidir en la LAN hacen merge **last-write-wins** con `updated_at`/tombstones. Best-effort y opt-in por dispositivo.
- **Backup sin nube**: exportación manual de la configuración a archivo cifrado desde Ajustes.
- El motor de merge es agnóstico del transporte: si en v2+ se decidiera una nube opcional, se añadiría como otro transporte sin tocar el dominio.

## 5. Distribución por plataforma

| Plataforma | Canal | Requisitos / notas |
|---|---|---|
| Windows | Microsoft Store (MSIX) + instalador directo | Firma de código |
| Linux | Flathub + AUR | Flatpak como canal principal |
| Android | Google Play | Cuenta dev 25 USD única |
| Android TV / Fire TV | Google Play (TV) + Amazon Appstore | Banner leanback, navegación D-pad auditada |
| iOS | App Store | 99 USD/año; política estricta con IPTV: reproductor 100 % genérico, sin contenido (P4). Declarar el uso de Red Local (mDNS) en Info.plist |
| LG webOS | LG Content Store | Alta gratuita; QA propio de LG; Dev Mode para pruebas en TV física |

## 6. Metodología y tooling de IA
- **SDD (protocolo 11 del vault)**: los artefactos de esta carpeta se espejan en `.specify/` del repo. Cada fase arranca actualizando spec/plan/tasks si hubo cambios.
- **Claude Code con codebase-memory-mcp — obligatorio** (norma 2 del proyecto; sustituye a Graphify por ADR-005). Setup en Fase 0:
  1. Instalación manual verificada por checksum (SHA-256) del binario, no `curl | bash`
  2. `.cbmignore` (equivalente al antiguo `.graphifyignore`: build/, *.g.dart, lockfiles, assets binarios)
  3. `auto_index=true` / `auto_watch=true` — indexado inicial y reindexado en background tras cada cambio, sin ritual manual
  4. Artefacto de equipo `.codebase-memory/graph.db.zst` comiteado (para que un compañero que clona el repo arranque desde ahí)
  5. Herramientas MCP disponibles durante toda la sesión: `get_architecture`, `trace_path`, `search_graph`, `detect_changes`, `search_code`, `query_graph` (Cypher read-only), entre otras
- **Memoria y handoff**: handoff al cerrar cada sesión (protocolo 12); bitácora en el diario.
- **ADRs** en MADR para toda decisión arquitectónica; **conventional commits**; PRs pequeñas por tarea; CI verde como condición de merge.

## 7. Roadmap por fases
Estimaciones para un desarrollador + Claude Code, dedicación parcial.

| Fase | Contenido | Salida verificable | Estimación |
|---|---|---|---|
| **F0 · Setup** | Repo, Melos, CI, codebase-memory-mcp, CLAUDE.md, `.specify/` | Pipeline verde con app esqueleto en Win/Linux/Android | 1 semana |
| **F1 · Núcleo** | Parsers M3U/XMLTV (TDD, golden files), cliente Xtream, drift + FTS5, **spikes S1–S5** (reproducción ×4 + red local) | `packages/` con cobertura alta; informe de spikes | 3–4 semanas |
| **F2 · Desktop MVP** | App Windows/Linux completa según ui-spec. **Gate D2 (licencia)** | Beta privada de escritorio usable a diario | 3 semanas |
| **F3 · Android + TV + emparejamiento** | Shells touch y TV, media3, rejilla EPG y **HU-08 completo** (QR/código, transferencia LAN) — el onboarding de TV lo exige | APK móvil configura la Fire TV real en < 60 s | 4–5 semanas |
| **F4 · webOS** | Port `flutter-webos`, vídeo del sistema, empaquetado IPK, Dev Mode | App + emparejamiento funcionando en LG física | 3–4 semanas |
| **F5 · iOS** | Build iOS, AVPlayer (según S3), permiso Red Local, escáner QR | TestFlight | 2–3 semanas |
| **F6 · Sync LAN automática (premium)** | Claves de dispositivo, descubrimiento en background, merge LWW, pantalla Dispositivos completa | Favorito creado en el PC aparece solo en la TV al abrirla | 2 semanas |
| **F7 · Lanzamiento** | Pulido, i18n (D4), altas en los 6 canales, beta pública | Publicación coordinada | 2–3 semanas |

Total orientativo: **4,5–5,5 meses** de dedicación parcial sostenida (el backend eliminado descuenta ~1 mes respecto a la revisión 1.0).

## 8. Riesgos y mitigaciones

| # | Riesgo | Prob. | Impacto | Mitigación |
|---|---|---|---|---|
| R1 | `flutter-webos` reciente: lagunas en plugins (vídeo, red, almacenamiento seguro) | Media | Alto | Spikes S4/S5; plan B: app web webOS mínima reutilizando diseño y protocolo de emparejamiento |
| R2 | MPEG-TS crudo en iOS sin componentes GPL | Media | Medio | Spike S3; VLCKit (LGPL) como fallback aceptado por P8 |
| R3 | Políticas de App Store / LG contra apps IPTV | Media | Alto | P4 estricto; precedentes aprobados (open-tv está en App Store) |
| R4 | Dialectos no estándar de paneles Xtream y M3U rotos | Alta | Medio | P7: golden files reales; parser tolerante que degrada, no aborta |
| R5 | Rendimiento en TVs de gama baja | Media | Alto | RNF-04 medido en hardware real desde F3; listas virtualizadas |
| R6 | Curva de Dart para el equipo | Baja | Bajo | Claude Code + F1 empieza por paquetes puros sin UI |
| R7 | D2 (licencia) se retrasa y bloquea el player de escritorio | Media | Medio | Gate explícito en F2; `PlayerPort` desacopla mientras tanto |
| R8 | Alcance creciente (DVR, Tizen, nube…) | Alta | Medio | SDD: nada entra sin pasar por spec + plan; v2 como backlog |
| R9 | mDNS/multicast bloqueado (aislamiento AP, permisos iOS Red Local, APIs webOS) | Media | Medio | El flujo QR lleva IP:puerto y no depende de mDNS; IP manual como último recurso; spike S5 |
| R10 | Sin nube: usuario espera sync fuera de casa o backup automático | Media | Bajo | Comunicación clara en la UI ("en tu red"), exportación a archivo, opción nube opt-in evaluable en v2 (ADR-002, opción C) |

## 9. Costes operativos estimados

Cuentas de desarrollador: Google Play 25 USD (única), Apple 99 USD/año, Amazon y LG gratuitas, Microsoft ~19 USD (única). **Infraestructura: 0 €** — no hay backend que operar (ADR-002). CI: GitHub Actions (gratis si open source; minutos incluidos si privado). Firma de código Windows: opcional al inicio.

## 10. Criterios de éxito de v1

1. Importar una lista real de 100k canales en < 30 s con UI fluida, en un portátil medio.
2. Búsqueda < 100 ms percibida en todas las plataformas.
3. **Configurar una TV desde el móvil (QR o código) en menos de 60 segundos**, y ver converger favoritos/progreso automáticamente entre dispositivos emparejados en la misma red.
4. Publicado y aprobado en los 6 canales de distribución de §5.
5. Cero dependencias GPL en el build si D2 se resuelve como "comercial" (o compromiso documentado en ADR si open source).
6. Cero datos de usuario almacenados en servidores del proyecto (verificable por diseño).


---

## Revisión 1.2 — 2026-07-21 · iOS aplazado a v1.1

**Motivo**: no hay Mac disponible. Compilar, firmar y distribuir una app iOS lo requiere sin alternativa viable a corto plazo (Xcode solo corre en macOS). Es una restricción de recursos, no un cambio de arquitectura: no requiere ADR.

**Qué cambia respecto a la revisión 1.1:**

- La **Fase 5 (iOS)** sale del alcance de la v1 y pasa a **v1.1**, junto con el **spike S3** (AVPlayer vs VLCKit), que también necesita Mac. iOS sigue siendo objetivo del producto, solo se desplaza en el tiempo.
- **Roadmap de la v1** (sustituye a la tabla de §7): F0 Setup (sem. 1) · F1 Núcleo + **4 spikes** (sem. 2–4) · F2 Desktop MVP (sem. 5–7) · F3 Android + TV + emparejamiento (sem. 8–12) · F4 webOS (sem. 13–16) · F6 Sync LAN premium (sem. 17–18) · F7 Lanzamiento (sem. 19–21). Total: **21 semanas** (antes 24).
- **Distribución (§5)**: la v1 sale por **5 canales** — Microsoft Store, Flathub/AUR, Google Play, Amazon Appstore y LG Content Store. App Store queda para la v1.1.
- **Criterio de éxito nº4 (§10)**: "publicado y aprobado en los **5** canales de la v1" (antes 6).
- **Costes (§9)**: se difieren los 99 USD/año de Apple Developer hasta la v1.1.
- **Spikes de F1**: quedan cuatro (S1 media3, S2 desktop, S4 webOS, S5 red local). El informe de spikes (T1.8) no cubrirá iOS.

**Por qué el impacto técnico es mínimo**: el principio P6 (el dominio no conoce al reproductor) y la abstracción `PlayerPort` ya aíslan el motor de reproducción por plataforma; iOS se implementa después como una implementación más del puerto, sin tocar `core`, `protocols`, `data` ni `pairing`. Lo mismo aplica al emparejamiento: el núcleo de `pairing` es agnóstico de plataforma y ya se testea sin red.

**Condición de reactivación**: disponer de un Mac (propio, alquilado en la nube o runner macOS de pago en CI) + alta en Apple Developer. En ese momento se replanifica la fase iOS como v1.1 con una ronda SDD corta (revisar spec/plan/tasks, ejecutar el spike aplazado y luego los 3 sprints).

> Nota de sincronización: Notion ya refleja esta revisión — 3 sprints iOS + 11 tareas marcados *Aplazado a v1.1*, sprints renumerados a S0–S20, vistas "1 · Cronológico v1 (S0→S20)" y "3 · v1.1 aplazado (iOS)". Este vault (plan/spec/tasks) es la fuente de verdad; Notion es el espejo operativo.


## Revisión 1.3 — 2026-07-29 · tooling de código (ADR-005)

**Motivo**: ADR-005 — Graphify sustituido por `codebase-memory-mcp` tras un spike de validación decisivo (Graphify no encontraba `resolveConflict`; codebase-memory-mcp sí, junto con métricas estructurales que Graphify no daba). Migración ejecutada en el repo (commit `8e45795`) y watcher confirmado en vivo (auto-reindexado tras el commit, sin ritual manual).

**Qué cambia respecto a la revisión 1.2** (aplicado directamente en §1, §3, §4.1, §6 y §7 de arriba, sin dejar rastro de la redacción anterior): norma 2 del proyecto pasa de "Graphify obligatorio" a "codebase-memory-mcp obligatorio"; el árbol del monorepo sustituye la junction `graphify-out/` por el artefacto de equipo comiteado `.codebase-memory/graph.db.zst` + `.cbmignore`; el setup de Fase 0 sustituye los 8 pasos de CLI de Graphify por instalación verificada por checksum + auto-indexado por watcher; no requiere cambios de alcance, arquitectura ni roadmap — es una sustitución de herramienta de tooling interno, sin impacto en el producto.


## Revisión 1.4 — 2026-07-31 · D4 idiomas resuelto (español + inglés)

**Decisión** (usuario, 2026-07-31, sesión del chat de coordinación): **v1 soporta español e inglés**. Cierra la clarificación C3 de spec y la decisión abierta D4 desde el Sprint 0.

**Razones** (extracto de la deliberación, ver handoff entrada del 2026-07-31 "D4 idiomas cerrada"):
- Cubre ~80% del público objetivo real de una app IPTV en las 4 tiendas de v1 (Play, Amazon, LG Content Store, más el ecosistema de instalación lateral desktop) con coste marginal casi nulo.
- Inglés es la lingua franca del público técnico de nicho (comunidad de reproductores IPTV en GitHub, Reddit, foros) al que naturalmente llega el boca-oreja de una app que hace las cosas bien.
- Portugués BR y francés (opción C evaluada) descartados **para v1**, no descartados en absoluto: la arquitectura queda preparada para añadirlos aditivamente (nuevo `.arb`, sin cambios de código) y se re-evaluará al cerrar F5 con datos reales de descargas por región del early access.
- Coherente con P7 (calidad verificable): sistema tipado oficial de Flutter, no cadenas mágicas por clave string.
- No compromete P8: `flutter_localizations` es Apache-2.0; `intl` es BSD-3.

**Decisiones de arquitectura derivadas** (aplican desde la primera implementación, tarea de S2 "Decisión D4 + i18n base"):

1. **Sistema**: `flutter_localizations` + `intl` + archivos `.arb`. Generación de código vía `flutter gen-l10n` (tipado, autocompletado, validación en tiempo de compilación).
2. **Idioma base del código fuente**: **inglés** (`en`) — claves del `.arb` en inglés, no en español. Es la convención estándar de Flutter/Android/iOS y no rompe nada el día que se añada un tercer idioma.
3. **Locales soportadas en v1**: `en` (base) y `es`. Un `.arb` por locale en `packages/app/lib/l10n/` (o donde acabe cayendo el paquete de UI raíz según el layout monorepo final de S2).
4. **Idioma por defecto**: cuando la locale del sistema no es ni `en` ni `es`, la app cae a **inglés**. Decidido con el usuario (2026-07-31) frente a la alternativa "español por defecto".
5. **Formato de fecha/hora, unidades, pluralización**: delegados a `intl` con la locale activa. Sin código propio de formateo por locale.
6. **Detección de locale**: la del sistema, con opción de override manual en Ajustes (patrón estándar de Flutter con `Locale? locale` en `MaterialApp`). Diseño de la pantalla de Ajustes lo materializa cuando toque en F2/F3.

**Aplazado explícitamente, no olvidado**:
- **Portugués BR y francés**: evaluación en el cierre de F5 (Sync LAN) con datos reales de early access. No requiere ADR ni cambio de arquitectura para añadirlos; sólo `.arb` nuevo + traducción con revisor nativo + QA visual (francés alarga cadenas ~20%, atención al shell TV con foco).
- **Cadenas de tienda (App Store, Play, Amazon, LG Content Store)**: título/descripción/keywords/capturas rotuladas. Se traducen fuera del código, en la consola de cada tienda. **Decisión aplazada a F7** (lanzamiento): idiomas y granularidad por decidir con datos de early access. No es blocker de código ni bloquea el cierre de S2. Registrada como C5 abierta en spec § Clarificaciones.
- **Right-to-left**: no aplica en v1 (no soportamos árabe/hebreo). El layout de Flutter lo soporta nativamente; no requiere trabajo específico hoy.

**Sin ADR nuevo**: no hay renuncia arquitectónica ni compromiso a hipotecar el modelo de negocio; es aplicar la convención oficial de Flutter con un idioma más que sólo ES. Si en el futuro se cambiara a un sistema no oficial (ej. `easy_localization` sin codegen), esa sí sería una decisión con ADR.


## Revisión 1.5 — 2026-08-01 · Motor de reproducción de escritorio decidido (media_kit/libmpv)

**Decisión** (Claude Code, S3 · Spike de escritorio, con criterios y pesos aprobados por
el usuario antes de medir): **Windows y Linux usan media_kit (libmpv, LGPLv2.1+/LGPLv3)**
como motor de reproducción. Cierra la elección que §4.3 dejaba abierta ("se decide en el
gate de licencia D2").

**Hallazgos que motivaron el spike** (ver `docs/bench/S3-desktop-spike.md` completo):

1. **Corrección de un error de este propio documento y de `constitution.md` (P8)**:
   ambos citaban "libmpv" como GPL sin matizar que mpv es dual-licenciado. El build real
   que `media_kit` distribuye usa el modo LGPL (`-Dgpl=false`/`--disable-gpl`), verificado
   contra los repos de build oficiales, no de memoria.
2. **`dart_vlc` está descontinuado** (archivado en GitHub desde 2024, pub.dev lo marca
   "replaced by: media_kit") y **`flutter_vlc_player` no cubre escritorio** (solo
   Android/iOS) — no existe ningún binding Flutter viable para libVLC en Windows/Linux
   hoy.
3. **El binario oficial de libVLC (`vlc-3.0.23-win64.zip`) se distribuye en modo GPL por
   defecto** — confirmado leyendo el `COPYING.txt` embarcado. Queda descartado bajo la
   regla de veto de licencia acordada para el spike, y también pierde en la comparativa
   ponderada sin aplicar el veto.

**Matriz de decisión** (criterios y pesos acordados con el usuario antes de medir):
C1 formatos reales 30 %, C2 licencia 25 % (con veto), C3 bindings mantenidos 20 %, C5
control programático 12 %, C6 estabilidad 8 %, C4 footprint 5 %. Resultado: media_kit
4,83/5 ponderado; libVLC vetado (2,42/5 si se ignorase el veto — tampoco ganaría).

**Medición real** (Windows, corpus de 13 entradas: 9 canales live variados del catálogo
de iptv-org ya en el repo + 4 fixtures VOD del Matroska Test Suite, CC BY): media_kit
reproduce 11/13 (falla solo en un HTTP 403 de origen y una URL DASH con firma caducada,
ambos fallos idénticos también en libVLC); libVLC reproduce 10/13, fallando además en la
única fuente HEVC del corpus, que media_kit sí resuelve. Footprint: +46,3 MB en Windows
(dominado por `libmpv-2.dll`, 28,4 MB), **solo +63 KB en Linux** (enlace dinámico contra
el `libmpv` del sistema, sin binario embarcado) — frente a 142-191 MB del runtime
redistribuible de libVLC.

**Riesgos residuales anotados**: reproducción real en Linux no verificada este sprint
(solo build/footprint); `libmpv-dev` es dependencia de *build* en Linux, no solo de
runtime (confirmado empíricamente — el job de CI del spike falló hasta añadir
`apt-get install libmpv-dev`), así que `ci.yml` necesitará el mismo paquete cuando
`packages/player` adopte media_kit; dependencia de un mantenedor pequeño sin respaldo
corporativo, mitigada por `PlayerPort` (P6).

**ADR nuevo**: ADR-009
(implicación no obvia: corrección de una afirmación de licencia incorrecta ya publicada
en `constitution.md`/este documento, más el compromiso de mantener el enlace dinámico).

**Sin cambio de alcance de v1.1/v2**: media3 sobre AVD (spike parcial opcional del
consenso de cierre de S2) se descartó explícitamente para no robar foco al comparativo de
escritorio — se cubre en S3.5 con Fire OS real.
