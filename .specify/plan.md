# Plan de desarrollo — Reproductor IPTV Multiplataforma

> Espejo de `02-Proyectos/Reproductor IPTV Multiplataforma/plan.md` (rev. 1.2) en el vault. Ver `.specify/README.md` para la regla de sincronización.

> Revisión 1.1: sincronización rediseñada como **serverless** por decisión del usuario (ADR-002). Desaparece el backend de v1. Revisión 1.2 (más abajo): iOS aplazado a v1.1.

## 1. Resumen ejecutivo

Se propone construir el reproductor IPTV con **Flutter/Dart como base de código única** para Windows, Linux, Android, iOS, Android TV/Fire TV y LG webOS, con arquitectura limpia local-first sobre SQLite, reproducción delegada en motores nativos por plataforma tras una abstracción, y **sincronización sin servidores**: emparejamiento por QR/código de 6 dígitos y transferencia + sync automática por red local. La ventana de oportunidad es real: LG publicó oficialmente el SDK `flutter-webos` y Samsung mantiene `flutter-tizen`, lo que convierte a Flutter en el único stack que hoy alcanza *todas* las plataformas objetivo con un solo equipo — camino vetado para open-tv (Tauri + mpv externo).

Ejecución por 7 fases (F0–F7) con un *gate* de decisión (licencia en F2), metodología SDD, Claude Code con **Graphify obligatorio** y memoria del proyecto en el vault. Coste de infraestructura: **cero**.

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

Decisiones formales en ADR-001 (Elección de stack multiplataforma) y ADR-002 (Sincronización serverless por emparejamiento local).

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
| Tooling IA | Claude Code + Graphify + Spec Kit | — | §6 |

**Nota sobre Dart**: no está hoy en el stack del usuario (TS/PHP-Laravel); la curva desde TypeScript es corta y Claude Code reduce el coste de adopción (riesgo R6).

## 4. Arquitectura técnica

### 4.1 Estructura del monorepo

```
iptv-player/                   # repo real: IPTVapp (ver nota del Sprint 0 en el handoff)
├── .specify/                  # Artefactos SDD (espejo de esta carpeta del vault)
├── CLAUDE.md                  # Instrucciones del repo para Claude Code (Graphify incluido)
├── melos.yaml
├── packages/
│   ├── core/                  # Dominio puro: entidades, casos de uso, puertos. Sin Flutter.
│   ├── protocols/             # Parsers M3U y XMLTV (streaming) + cliente Xtream. Sin Flutter.
│   ├── data/                  # drift/SQLite, FTS5, repositorios, almacén seguro de credenciales
│   ├── player/                # PlayerPort + implementaciones por plataforma
│   └── pairing/                # Emparejamiento QR/código, canal local cifrado, motor de sync LWW
├── apps/
│   └── app/                   # App Flutter única; targets: windows, linux, android, ios, webos
└── graphify-out/               # Grafo del código (junction → carpeta del proyecto en el vault)
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
| iOS (v1.1) | AVPlayer nativo; *fallback* VLCKit si los TS crudos fallan | — / LGPL-2.1 | HLS ✅ nativo; TS ⚠️ (spike S3, aplazado) |
| Windows / Linux | media_kit (libmpv) **o** libVLC — se decide en el gate de licencia D2 | GPL / LGPL | Todo ✅ |
| LG webOS | Pipeline multimedia del sistema vía plugins `flutter-webos` | — | Spike S4 obligatorio |

### 4.4 Capa de presentación

Tres shells sobre los mismos view-models (Riverpod): `TvShell` (10-foot, D-pad, foco visible), `MobileShell` (touch) y `DesktopShell` (atajos). Detección por plataforma + factor de forma (Android TV por *leanback feature*). Inventario completo de pantallas, campos y estados: `ui-spec.md`.

### 4.5 Transferencia y sincronización sin servidor (ADR-002)

- **Emparejamiento**: el receptor (típicamente la TV) muestra un QR y un código de 6 dígitos. El QR contiene `{host, port, token efímero}` — nunca credenciales — y no depende de mDNS. El código es la vía sin cámara: mDNS (`_iptvpair._tcp`) localiza al receptor y el código autentica el canal. Último recurso: IP manual.
- **Canal local**: WebSocket embebido en el receptor, cifrado con clave de sesión derivada del token/código. Por él viaja el paquete de configuración (fuentes con secretos, favoritos, progreso, ajustes — el usuario elige qué).
- **Sync automática (premium)**: dispositivos ya emparejados intercambian claves de dispositivo; al coincidir en la LAN hacen merge **last-write-wins** con `updated_at`/tombstones. Best-effort y opt-in por dispositivo.
- **Backup sin nube**: exportación manual de la configuración a archivo cifrado desde Ajustes.
- El motor de merge es agnóstico del transporte: si en v2+ se decidiera una nube opcional, se añadiría como otro transporte sin tocar el dominio.

## 5. Distribución por plataforma (v1: 5 canales)

| Plataforma | Canal | Requisitos / notas |
|---|---|---|
| Windows | Microsoft Store (MSIX) + instalador directo | Firma de código |
| Linux | Flathub + AUR | Flatpak como canal principal |
| Android | Google Play | Cuenta dev 25 USD única |
| Android TV / Fire TV | Google Play (TV) + Amazon Appstore | Banner leanback, navegación D-pad auditada |
| LG webOS | LG Content Store | Alta gratuita; QA propio de LG; Dev Mode para pruebas en TV física |

iOS (App Store) queda para **v1.1**: 99 USD/año diferidos; política estricta con IPTV (reproductor 100 % genérico, sin contenido, P4); declarar el uso de Red Local (mDNS) en Info.plist cuando se retome.

## 6. Metodología y tooling de IA

- **SDD (protocolo 11 del vault)**: los artefactos de esta carpeta se espejan en `.specify/` del repo. Cada fase arranca actualizando spec/plan/tasks si hubo cambios.
- **Claude Code con Graphify — obligatorio** (norma 2 del proyecto). Setup en Fase 0:
  1. `uv tool install graphifyy`
  2. `.gitignore`: `graphify-out/`, `.graphifyignore`, `.claude/skills/graphify/`
  3. `.graphifyignore` (build/, *.g.dart, lockfiles, assets binarios)
  4. `graphify install --project` · 5. `graphify claude install`
  6. `graphify . --obsidian` → grafo + `GRAPH_REPORT.md`
  7. Junction `graphify-out/` → carpeta del proyecto en el vault
  8. Tras cambios: `graphify update .` (sin coste de API)
- **Memoria y handoff**: `handoff.md` al cerrar cada sesión (protocolo 12); bitácora en el diario.
- **ADRs** en MADR para toda decisión arquitectónica; **conventional commits**; PRs pequeñas por tarea; CI verde como condición de merge.

## 7. Roadmap por fases (v1, revisión 1.2 — 21 semanas)

| Fase | Contenido | Salida verificable | Semanas |
|---|---|---|---|
| **F0 · Setup** | Repo, Melos, CI, Graphify, CLAUDE.md, `.specify/` | Pipeline verde con app esqueleto en Win/Linux/Android | 1 |
| **F1 · Núcleo** | Parsers M3U/XMLTV (TDD, golden files), cliente Xtream, drift + FTS5, **spikes S1/S2/S4/S5** | `packages/` con cobertura alta; informe de spikes | 2–4 |
| **F2 · Desktop MVP** | App Windows/Linux completa. **Gate D2 (licencia)** | Beta privada de escritorio usable a diario | 5–7 |
| **F3 · Android + TV + emparejamiento** | Shells touch y TV, media3, rejilla EPG y **HU-08 completo** | APK móvil configura la Fire TV real en < 60 s | 8–12 |
| **F4 · webOS** | Port `flutter-webos`, vídeo del sistema, empaquetado IPK, Dev Mode | App + emparejamiento funcionando en LG física | 13–16 |
| **F6 · Sync LAN automática (premium)** | Claves de dispositivo, descubrimiento en background, merge LWW | Favorito creado en el PC aparece solo en la TV al abrirla | 17–18 |
| **F7 · Lanzamiento** | Pulido, i18n (D4), altas en los 5 canales, beta pública | Publicación coordinada | 19–21 |

**F5 · iOS** queda fuera de este roadmap: es v1.1, sin fecha, condicionada a disponer de Mac.

## 8. Riesgos y mitigaciones

| # | Riesgo | Prob. | Impacto | Mitigación |
|---|---|---|---|---|
| R1 | `flutter-webos` reciente: lagunas en plugins (vídeo, red, almacenamiento seguro) | Media | Alto | Spikes S4/S5; plan B: app web webOS mínima reutilizando diseño y protocolo de emparejamiento |
| R2 | MPEG-TS crudo en iOS sin componentes GPL | Media | Medio | Spike S3 (v1.1); VLCKit (LGPL) como fallback aceptado por P8 |
| R3 | Políticas de App Store / LG contra apps IPTV | Media | Alto | P4 estricto; precedentes aprobados (open-tv está en App Store) |
| R4 | Dialectos no estándar de paneles Xtream y M3U rotos | Alta | Medio | P7: golden files reales; parser tolerante que degrada, no aborta |
| R5 | Rendimiento en TVs de gama baja | Media | Alto | RNF-04 medido en hardware real desde F3; listas virtualizadas |
| R6 | Curva de Dart para el equipo | Baja | Bajo | Claude Code + F1 empieza por paquetes puros sin UI |
| R7 | D2 (licencia) se retrasa y bloquea el player de escritorio | Media | Medio | Gate explícito en F2; `PlayerPort` desacopla mientras tanto |
| R8 | Alcance creciente (DVR, Tizen, nube…) | Alta | Medio | SDD: nada entra sin pasar por spec + plan; v2 como backlog |
| R9 | mDNS/multicast bloqueado (aislamiento AP, permisos iOS Red Local, APIs webOS) | Media | Medio | El flujo QR lleva IP:puerto y no depende de mDNS; IP manual como último recurso; spike S5 |
| R10 | Sin nube: usuario espera sync fuera de casa o backup automático | Media | Bajo | Comunicación clara en la UI ("en tu red"), exportación a archivo, opción nube opt-in evaluable en v2 (ADR-002, opción C) |

## 9. Costes operativos estimados

Cuentas de desarrollador: Google Play 25 USD (única), Amazon y LG gratuitas, Microsoft ~19 USD (única). Apple 99 USD/año diferidos a v1.1. **Infraestructura: 0 €** — no hay backend que operar (ADR-002). CI: GitHub Actions.

## 10. Criterios de éxito de v1

1. Importar una lista real de 100k canales en < 30 s con UI fluida, en un portátil medio.
2. Búsqueda < 100 ms percibida en todas las plataformas.
3. **Configurar una TV desde el móvil (QR o código) en menos de 60 segundos**, y ver converger favoritos/progreso automáticamente entre dispositivos emparejados en la misma red.
4. Publicado y aprobado en los **5 canales** de la v1 (§5).
5. Cero dependencias GPL en el build si D2 se resuelve como "comercial" (o compromiso documentado en ADR si open source).
6. Cero datos de usuario almacenados en servidores del proyecto (verificable por diseño).

---

## Revisión 1.2 — iOS aplazado a v1.1

**Motivo**: no hay Mac disponible. Compilar, firmar y distribuir una app iOS lo requiere sin alternativa viable a corto plazo (Xcode solo corre en macOS). Es una restricción de recursos, no un cambio de arquitectura: no requiere ADR.

**Qué cambia respecto a la revisión 1.1:**

- La **Fase 5 (iOS)** sale del alcance de la v1 y pasa a **v1.1**, junto con el **spike S3** (AVPlayer vs VLCKit), que también necesita Mac.
- **Roadmap de la v1**: F0 Setup (sem. 1) · F1 Núcleo + **4 spikes** (sem. 2–4) · F2 Desktop MVP (sem. 5–7) · F3 Android + TV + emparejamiento (sem. 8–12) · F4 webOS (sem. 13–16) · F6 Sync LAN premium (sem. 17–18) · F7 Lanzamiento (sem. 19–21). Total: **21 semanas** (antes 24).
- **Distribución (§5)**: la v1 sale por **5 canales** — Microsoft Store, Flathub/AUR, Google Play, Amazon Appstore y LG Content Store. App Store queda para la v1.1.
- **Criterio de éxito nº4 (§10)**: "publicado y aprobado en los **5** canales de la v1" (antes 6).
- **Costes (§9)**: se difieren los 99 USD/año de Apple Developer hasta la v1.1.
- **Spikes de F1**: quedan cuatro (S1 media3, S2 desktop, S4 webOS, S5 red local). El informe de spikes (T1.8) no cubrirá iOS.

**Por qué el impacto técnico es mínimo**: el principio P6 (el dominio no conoce al reproductor) y la abstracción `PlayerPort` ya aíslan el motor de reproducción por plataforma; iOS se implementa después como una implementación más del puerto, sin tocar `core`, `protocols`, `data` ni `pairing`. Lo mismo aplica al emparejamiento: el núcleo de `pairing` es agnóstico de plataforma y ya se testea sin red.

**Condición de reactivación**: disponer de un Mac (propio, alquilado en la nube o runner macOS de pago en CI) + alta en Apple Developer. En ese momento se replanifica la fase iOS como v1.1 con una ronda SDD corta (revisar spec/plan/tasks, ejecutar el spike aplazado y luego los 3 sprints).
