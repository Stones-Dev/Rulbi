<div align="center">

# Rulbi 📺

**The Modern, High-Performance, Open-Source Multi-Platform IPTV Platform**  
*Desktop (Windows, Linux, macOS) • Mobile (Android, iOS) • Smart TV (Android TV, Fire TV, LG webOS)*

[![CI](https://github.com/Stones-Dev/Rulbi/actions/workflows/ci.yml/badge.svg)](https://github.com/Stones-Dev/Rulbi/actions)
[![License: LGPL / MIT / BSD-3](https://img.shields.io/badge/License-Open--Source-blue.svg)](https://github.com/Stones-Dev/Rulbi)
[![Flutter Version](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)](https://flutter.dev)
[![Dart Version](https://img.shields.io/badge/Dart-3.5+-0175C2?logo=dart)](https://dart.dev)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](https://github.com/Stones-Dev/Rulbi/pulls)

---

[English](#-english) • [Español](#-español)

---

</div>

> ⚠️ **Disclaimer / Descargo de responsabilidad**  
> **Rulbi is strictly a media player and content-neutral platform.** It does **NOT** provide, host, bundle, scrape, resell, or distribute any IPTV playlists, streams, channels, or media content of any kind. Users must provide their own legitimate content and credentials. Rulbi is not affiliated with any third-party IPTV service provider.

---

<a name="english"></a>
# 🇬🇧 English

## 📖 Table of Contents
- [About Rulbi](#about-rulbi)
- [Why Rulbi? (Key Differences)](#why-rulbi-key-differences)
- [Core Features](#core-features)
- [Architecture & Tech Stack](#architecture--tech-stack)
- [Monorepo Structure](#monorepo-structure)
- [Supported Platforms & Form Factors](#supported-platforms--form-factors)
- [Getting Started & Build Instructions](#getting-started--build-instructions)
- [Testing & Quality Assurance](#testing--quality-assurance)
- [Undated Product Roadmap](#undated-product-roadmap)
- [Contributing](#contributing)
- [License](#license)

---

## About Rulbi

**Rulbi** is a next-generation, local-first, open-source IPTV client crafted with **Flutter & Dart**. Built upon a clean architecture monorepo, Rulbi delivers a seamless experience across all form factors: personal computers, touch-screen smartphones, and 10-foot living-room Smart TVs.

Unlike traditional IPTV apps that offer clunky interfaces, freeze when loading large playlists, or force users to type long credentials using a TV remote, Rulbi is designed from the ground up for speed, elegance, user privacy, and zero server lock-in.

---

## Why Rulbi? (Key Differences)

| Challenge in Existing Players | How Rulbi Solves It |
|---|---|
| **Massive Playlists Freeze the UI** | Chunked, streaming parsers running in background Dart isolates load 100,000+ channels smoothly without blocking the UI thread. |
| **TV UIs Are Just Stretched Mobile Apps** | Bespoke **10-foot UI (`TvShell`)** specifically designed for remote control D-pad navigation, high-contrast focus rings, and Leanback experience. |
| **Painful TV Setup** | **Serverless Cross-Device Onboarding**: Scan a QR code or enter a 6-digit PIN on your phone/PC to instantly beam your sources to your TV over local Wi-Fi. |
| **Slow Search Across Huge Catalogs** | **SQLite + FTS5 full-text search** delivers instant (< 100 ms) search across all channels, movies, and series with accent normalization. |
| **Cloud Dependency & Privacy Concerns** | **100% Local-First & Serverless**: Zero accounts, zero external servers, zero telemetry. All credentials stay encrypted on your device. |

---

## Core Features

### 📡 Playlist & Protocol Support
- **M3U & M3U8 Streaming**: Robust parser tolerant to malformed attributes and non-standard dialects (`tvg-id`, `tvg-name`, `tvg-logo`, `group-title`).
- **Xtream Codes API**: Full integration for Live TV, Movies (VOD), and TV Series with categories, metadata, and account status/expiration inspection.
- **XMLTV EPG Guide**: Support for uncompressed and gzip-compressed (`.xml.gz`) guides with time-windowed loading and automated background purging.
- **Multi-Source Management**: Maintain multiple active sources simultaneously, refresh on-demand, or toggle sources without losing customized data.

### 🎬 High-Performance Playback (`PlayerPort`)
- **Desktop (Windows & Linux)**: Hardware-accelerated playback via `media_kit` (libmpv, LGPL-2.1+), supporting HLS, MPEG-TS, MP4, MKV, HEVC, and multi-track audio/subtitles.
- **Mobile & Android TV / Fire TV**: Native **Media3 (ExoPlayer)** engine with Picture-in-Picture (PiP), background playback, and intuitive touch gestures (volume, brightness, seek).
- **Smart TV (LG webOS)**: Optimized web pipeline and CanvasKit 720p hardware acceleration for fluid 60 FPS navigation on limited TV hardware.

### ⚡ Seamless Organization & Discovery
- **Instant Search**: SQLite FTS5 search index provides sub-100ms results as you type.
- **Rich Catalogs**: Movie backdrops, series episode stills, season selectors, and plot overviews.
- **Continue Watching & Favorites**: Resume playback exactly where you left off; custom channel favoriting.

### 🔒 Serverless Cross-Device Sync & Pairing
- **Instant TV Onboarding**: Display a QR code or a 6-digit PIN on your TV, scan or type it from your phone, and transfer playlists securely over your local network.
- **Encrypted Local Channel**: WebSockets secured with ephemeral session keys—credentials never leave your home network.
- **Last-Write-Wins (LWW) Merge Engine**: Keep favorites, sources, and playback progress synchronized across all devices in the same Wi-Fi without any third-party cloud.

---

## Architecture & Tech Stack

Rulbi enforces **Clean Architecture** principles in a Melos monorepo. The core domain is completely decoupled from any UI framework or media engine:

```
apps/app  ──►  packages/{player, data, pairing}  ──►  packages/protocols  ──►  packages/core
                                                                                     ▲
                                                                          (zero dependencies)
```

- **Domain Isolation (Principle P6)**: `packages/core` and `packages/protocols` are pure Dart packages without any Flutter or native platform dependencies.
- **Reactive State Management**: Powered by **Riverpod** for predictable, testable, and robust state propagation.
- **Local-First Database**: **Drift (SQLite)** for type-safe relational storage and FTS5 full-text search.
- **Secure Storage**: Credentials encrypted at rest using platform-native secure enclaves (Android Keystore, Windows Credential Manager, Linux Secret Service / Keyring).

---

## Monorepo Structure

```
Rulbi/
├── apps/
│   └── app/               # Main Flutter application (TvShell, MobileShell, DesktopShell)
├── packages/
│   ├── core/              # Pure Dart domain: entities (Source, Channel, EpgProgram), ports (PlayerPort)
│   ├── protocols/         # Streaming parsers for M3U, XMLTV, and Xtream Codes HTTP client
│   ├── data/              # Drift / SQLite schema, FTS5 search index, credential storage
│   ├── player/            # Platform playback implementations (media_kit / libmpv, Media3, webOS)
│   ├── pairing/           # Serverless local pairing, QR/PIN payload, encrypted WS, LWW sync engine
│   └── tokens/            # Visual tokens: Inter typography, color palette, TV focus rings
├── installer/             # Inno Setup scripts (Windows) & Debian package scripts (Linux)
├── tool/                  # Developer utilities and test mock servers
└── .specify/              # Spec-Driven Development (SDD) design docs & specifications
```

---

## Supported Platforms & Form Factors

| Platform | Form Factor | Playback Engine | Input Method | Status |
|---|---|---|---|---|
| **Windows 10 / 11** | Desktop | `media_kit` (libmpv) | Keyboard, Mouse | ✅ Available |
| **Linux (Ubuntu, Arch, etc.)** | Desktop | `media_kit` (libmpv) | Keyboard, Mouse | ✅ Available |
| **Android (Phone & Tablet)** | Mobile | Android Media3 (ExoPlayer) | Touch, Gestures | ✅ Available |
| **Android TV & Fire TV** | Smart TV (10-ft) | Android Media3 (ExoPlayer) | D-pad Remote Control | ✅ Available |
| **LG webOS (22+)** | Smart TV (10-ft) | webOS HTML5 / WebApp CanvasKit | Magic Remote / D-pad | 🟡 Optimization |
| **Apple macOS & iOS** | Desktop / Mobile | Native AVPlayer | Keyboard / Touch | 📋 Planned (v1.1) |

---

## Getting Started & Build Instructions

### Prerequisites
- **Flutter SDK**: `>= 3.5.0`
- **Dart SDK**: `>= 3.5.0`
- **Melos**: Installed globally (`dart pub global activate melos`)
- **Platform Build Tools**:
  - *Windows*: Visual Studio 2022 with Desktop development with C++
  - *Linux*: `sudo apt-get install ninja-build libgtk-3-dev clang cmake pkg-config libmpv-dev libsecret-1-dev`
  - *Android*: Android SDK & JDK 17

### 1. Clone & Bootstrap
```bash
git clone https://github.com/Stones-Dev/Rulbi.git
cd Rulbi

# Activate Melos and bootstrap all monorepo packages
dart pub global activate melos
melos bootstrap
```

### 2. Code Generation
Rulbi uses code generation for Drift database models and Flutter localizations:
```bash
# Generate database schema in packages/data
cd packages/data
dart run build_runner build --delete-conflicting-outputs

# Generate localized strings in apps/app
cd ../../apps/app
flutter gen-l10n
cd ../..
```

### 3. Run the Application
```bash
# Run on Windows Desktop
flutter run -d windows -t apps/app/lib/main.dart

# Run on Linux Desktop
flutter run -d linux -t apps/app/lib/main.dart

# Run on Android Device / Emulator / Android TV
flutter run -d android -t apps/app/lib/main.dart
```

---

## Testing & Quality Assurance

Rulbi enforces **Test-Driven Development (TDD)** for protocol parsing and local sync engines against real-world golden files.

```bash
# Run static analysis across all monorepo packages
melos run analyze

# Run pure Dart and Flutter unit tests
melos run test

# Run Drift database tests specifically
cd packages/data
flutter test
```

---

## Undated Product Roadmap

Rulbi follows a staged, milestone-driven roadmap free from rigid calendar dates:

```
[Phase 1: Core & Desktop] ──► [Phase 2: Mobile & TV] ──► [Phase 3: LAN Pairing] ──► [Phase 4: Smart TV & iOS] ──► [Phase 5: Advanced Features]
```

### 📍 Phase 1 — Core Engine & Desktop MVP
- [x] High-performance M3U/M3U8 streaming parser with golden file test suites.
- [x] XMLTV EPG parser with gzip (`.xml.gz`) support and time-window caching.
- [x] Xtream Codes API client (Live, VOD, Series, categories).
- [x] Drift SQLite database with FTS5 instant search engine.
- [x] Windows & Linux desktop client powered by `media_kit` (libmpv).
- [x] Standalone Windows (Inno Setup) and Linux (.deb / portable) packaging.

### 📍 Phase 2 — Mobile & 10-Foot Smart TV Experience
- [x] Dedicated 10-foot `TvShell` with full D-pad remote navigation and focus rings.
- [x] Android Media3 (ExoPlayer) playback engine for mobile and TV.
- [x] Ergonomic `MobileShell` with touch gestures (brightness, volume, scrubbing) & PiP.
- [x] Interactive EPG schedule grid and on-screen TV search keyboard.
- [x] Channel detail views, season/episode browser, and VOD hero backdrops.

### 📍 Phase 3 — Serverless LAN Pairing & Multi-Device Sync
- [x] Serverless QR code and 6-digit PIN onboarding flow.
- [x] Encrypted local WebSocket communication channel.
- [x] Last-Write-Wins (LWW) conflict-free synchronization engine with tombstones.
- [ ] Automatic background LAN discovery for already-paired home devices.
- [ ] Export and import encrypted offline backups.

### 📍 Phase 4 — Smart TV Optimization & Ecosystem Expansion
- [ ] Optimized LG webOS package (CanvasKit 720p hardware profile).
- [ ] Samsung Tizen support research (`flutter-tizen`).
- [ ] macOS desktop build and code signing.
- [ ] iOS / iPadOS port with native AVPlayer engine and local network permissions.

### 📍 Phase 5 — Power-User Playback & Community Features
- [ ] Advanced audio track and subtitle offset synchronization.
- [ ] Multi-view / Picture-in-Picture multi-stream monitoring.
- [ ] Parental controls (PIN-protected categories and channels).
- [ ] Expanded community translations (French, Portuguese, German, Italian).

---

## Contributing

We welcome community contributions, bug reports, and pull requests!

1. **Fork the Repository** on GitHub (`https://github.com/Stones-Dev/Rulbi`).
2. **Create a Feature Branch**: `git checkout -b feat/amazing-feature`.
3. **Write Tests**: If you fix a parsing bug, provide a real-world golden fixture under `packages/protocols/test/fixtures/`.
4. **Follow Conventions**: Use [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `docs:`, `chore:`).
5. **Ensure CI Passes**: Run `melos run analyze` and `melos run test` before opening your PR.
6. **Open a Pull Request**.

---

## License

Rulbi is an open-source project. Its core packages (`core`, `protocols`, `pairing`, `tokens`, and `data`) are licensed under permissive open-source licenses (**MIT / BSD-3-Clause**), and the desktop playback engine links dynamically with libmpv under the **LGPL-2.1+ / LGPL-3.0** license, ensuring complete compliance and freedom for personal use.

---

<br/>

<a name="español"></a>
# 🇪🇸 Español

## 📖 Tabla de Contenidos
- [Acerca de Rulbi](#acerca-de-rulbi)
- [¿Por qué Rulbi? (Diferencias clave)](#por-qué-rulbi-diferencias-clave)
- [Características Principales](#características-principales)
- [Arquitectura y Stack Tecnológico](#arquitectura-y-stack-tecnológico)
- [Estructura del Monorepo](#estructura-del-monorepo)
- [Plataformas y Factores de Forma Soportados](#plataformas-y-factores-de-forma-soportados)
- [Guía de Inicio y Compilación](#guía-de-inicio-y-compilación)
- [Testing y Control de Calidad](#testing-y-control-de-calidad)
- [Roadmap de Producto (Sin fechas)](#roadmap-de-producto-sin-fechas)
- [Cómo Contribuir](#cómo-contribuir)
- [Licencia](#licencia-1)

---

## Acerca de Rulbi

**Rulbi** es una plataforma cliente de IPTV multiplataforma, de código abierto y orientada al concepto *local-first*, desarrollada con **Flutter y Dart**. Diseñada sobre un monorepo con arquitectura limpia, Rulbi proporciona una experiencia de usuario nativa y optimizada en cualquier dispositivo: ordenadores de escritorio, teléfonos móviles táctiles y televisores Smart TV con mando a distancia.

A diferencia de los reproductores tradicionales que sufren cuelgues con listas grandes, ofrecen interfaces móviles estiradas en pantalla grande o exigen teclear URLs kilométricas con el mando, Rulbi ha sido concebido desde cero para ofrecer rendimiento instantáneo, diseño cuidado, privacidad absoluta y cero dependencia de servidores en la nube.

---

## ¿Por qué Rulbi? (Diferencias clave)

| Problema en Reproductores Existentes | Cómo lo Resuelve Rulbi |
|---|---|
| **Cuelgues al Importar Listas Gigantes** | Parsers en streaming sobre *isolates* independientes de Dart que procesan más de 100.000 canales sin bloquear la interfaz. |
| **Interfaces de TV Mal Adaptadas** | Experiencia **10-foot UI (`TvShell`)** diseñada específicamente para navegación con cruceta (D-pad), foco de alto contraste y Leanback. |
| **Configuración Tediosa en el Televisor** | **Emparejamiento Serverless por Red Local**: Escanea un código QR o introduce un PIN de 6 dígitos desde el móvil/PC para transferir tus fuentes a la TV al instante. |
| **Búsqueda Lenta en Catálogos Enormes** | **Búsqueda instantánea SQLite + FTS5** con respuesta en < 100 ms insensible a mayúsculas y tildes. |
| **Privacidad y Dependencia de Cuentas** | **100% Local-First y Sin Servidores**: Sin registros, sin nube externa y sin telemetría. Las credenciales se guardan cifradas en tu propio dispositivo. |

---

## Características Principales

### 📡 Soporte de Protocolos y Fuentes
- **Listas M3U y M3U8 en Streaming**: Parser tolerante a dialectos no estándar y atributos heterogéneos (`tvg-id`, `tvg-name`, `tvg-logo`, `group-title`).
- **API Xtream Codes**: Integración completa para Canales en Directo, Películas (VOD) y Series, con categorías, sinopsis y comprobación del estado y caducidad de la cuenta.
- **Guía de Programación EPG (XMLTV)**: Compatible con guías `.xml` y comprimidas en `.xml.gz`, carga bajo demanda por ventana temporal y purga automática de programas antiguos.
- **Gestión Multi-Fuente**: Mantén múltiples listas activas, actualízalas bajo demanda y actívalas o desactívalas sin perder tus favoritos ni tu historial.

### 🎬 Motores de Reproducción Nativos (`PlayerPort`)
- **Escritorio (Windows y Linux)**: Aceleración por hardware mediante `media_kit` (libmpv, LGPL-2.1+), compatible con HLS, MPEG-TS sobre HTTP, MP4, MKV, HEVC y cambio de pistas de audio y subtítulos.
- **Móvil y Android TV / Fire TV**: Motor nativo **Media3 (ExoPlayer)** con Picture-in-Picture (PiP), reproducción en segundo plano y gestos táctiles de control (brillo, volumen, avance).
- **Smart TV (LG webOS)**: Pipeline optimizado con CanvasKit a 720p para garantizar 60 FPS en televisores con hardware limitado.

### ⚡ Organización y Búsqueda Instantánea
- **Búsqueda en Tiempo Real**: Motor FTS5 sobre SQLite que arroja resultados en menos de 100 ms mientras escribes.
- **Catálogo Enriquecido**: Carátulas, imágenes de fondo (*backdrops*), capturas de episodios, selector de temporadas y sinopsis.
- **Continuar Viendo y Favoritos**: Reanudación automática de películas y episodios en el segundo exacto donde los dejaste.

### 🔒 Emparejamiento y Sincronización Local Sin Servidor
- **Puesta en Marcha Inmediata en TV**: La TV muestra un código QR o un PIN de 6 dígitos; escanéalo con el móvil y transfiere tu configuración por la red local sin tocar el mando.
- **Canal Local Cifrado**: Comunicación directa por WebSockets locales con cifrado de sesión; tus credenciales jamás salen de tu hogar.
- **Motor de Sincronización LWW**: Fusión de datos (*Last-Write-Wins*) con *tombstones* para mantener favoritos y progreso alineados entre tus dispositivos en la misma Wi-Fi sin servidores externos.

---

## Arquitectura y Stack Tecnológico

Rulbi implementa una **Arquitectura Limpia** desacoplada mediante un monorepo gestionado con Melos:

```
apps/app  ──►  packages/{player, data, pairing}  ──►  packages/protocols  ──►  packages/core
                                                                                     ▲
                                                                           (sin dependencias)
```

- **Aislamiento del Dominio (Principio P6)**: `packages/core` y `packages/protocols` son paquetes Dart puros, completamente independientes de Flutter y de APIs del sistema.
- **Estado Reactivo**: Gestionado con **Riverpod**, garantizando inyección de dependencias predecible y testabilidad total.
- **Base de Datos Local-First**: **Drift (SQLite)** con soporte tipado en compilación e índices de búsqueda FTS5.
- **Almacenamiento Seguro**: Credenciales cifradas en reposo usando el almacén seguro nativo de cada plataforma (Keystore en Android, Credential Manager en Windows, Secret Service en Linux).

---

## Estructura del Monorepo

```
Rulbi/
├── apps/
│   └── app/               # Aplicación Flutter principal (TvShell, MobileShell, DesktopShell)
├── packages/
│   ├── core/              # Dominio puro en Dart: entidades (Source, Channel, EpgProgram), puertos (PlayerPort)
│   ├── protocols/         # Parsers en streaming de M3U, XMLTV y cliente HTTP para Xtream Codes
│   ├── data/              # Esquema Drift / SQLite, índice FTS5 y almacén seguro de credenciales
│   ├── player/            # Implementaciones del reproductor por plataforma (libmpv, Media3, webOS)
│   ├── pairing/           # Emparejamiento LAN, payload QR/PIN, canal WS cifrado y motor de sync LWW
│   └── tokens/            # Tokens visuales: tipografía Inter, colores y estilo de foco para TV
├── installer/             # Scripts de empaquetado para Windows (Inno Setup) y Linux (.deb / portable)
├── tool/                  # Servidores de pruebas y utilidades de automatización
└── .specify/              # Documentación y especificaciones del proyecto bajo metodología SDD
```

---

## Plataformas y Factores de Forma Soportados

| Plataforma | Factor de Forma | Motor de Vídeo | Interfaz y Control | Estado |
|---|---|---|---|---|
| **Windows 10 / 11** | Escritorio | `media_kit` (libmpv) | Teclado, Ratón | ✅ Disponible |
| **Linux (Ubuntu, Arch, etc.)** | Escritorio | `media_kit` (libmpv) | Teclado, Ratón | ✅ Disponible |
| **Android (Móvil / Tablet)** | Móvil | Android Media3 (ExoPlayer) | Táctil, Gestos | ✅ Disponible |
| **Android TV / Fire TV** | Smart TV (10-ft) | Android Media3 (ExoPlayer) | Mando a distancia (D-pad) | ✅ Disponible |
| **LG webOS (22+)** | Smart TV (10-ft) | webOS HTML5 / WebApp CanvasKit | Mando Magic / D-pad | 🟡 Optimización |
| **Apple macOS e iOS** | Escritorio / Móvil | AVPlayer Nativo | Teclado / Táctil | 📋 Planificado (v1.1) |

---

## Guía de Inicio y Compilación

### Requisitos Previos
- **Flutter SDK**: `>= 3.5.0`
- **Dart SDK**: `>= 3.5.0`
- **Melos**: Instalado globalmente (`dart pub global activate melos`)
- **Herramientas por Plataforma**:
  - *Windows*: Visual Studio 2022 con herramientas de C++ para escritorio
  - *Linux*: `sudo apt-get install ninja-build libgtk-3-dev clang cmake pkg-config libmpv-dev libsecret-1-dev`
  - *Android*: Android SDK y Java JDK 17

### 1. Clonar e Inicializar el Monorepo
```bash
git clone https://github.com/Stones-Dev/Rulbi.git
cd Rulbi

# Activar Melos y resolver dependencias del monorepo
dart pub global activate melos
melos bootstrap
```

### 2. Generación de Código
Rulbi utiliza generación de código para la base de datos Drift y los textos localizados:
```bash
# Generar el esquema de base de datos en packages/data
cd packages/data
dart run build_runner build --delete-conflicting-outputs

# Generar las clases de internacionalización en apps/app
cd ../../apps/app
flutter gen-l10n
cd ../..
```

### 3. Ejecutar la Aplicación
```bash
# Ejecutar en Windows de escritorio
flutter run -d windows -t apps/app/lib/main.dart

# Ejecutar en Linux de escritorio
flutter run -d linux -t apps/app/lib/main.dart

# Ejecutar en Móvil o emulador Android / Android TV
flutter run -d android -t apps/app/lib/main.dart
```

---

## Testing y Control de Calidad

Rulbi sigue **Desarrollo Guiado por Pruebas (TDD)** en sus motores de protocolos y sincronización, validando cada cambio contra un banco de pruebas de *golden files* reales.

```bash
# Ejecutar análisis estático en todos los paquetes
melos run analyze

# Ejecutar tests unitarios de Dart y Flutter
melos run test

# Ejecutar tests específicos de la base de datos
cd packages/data
flutter test
```

---

## Roadmap de Producto (Sin fechas)

El desarrollo de Rulbi se organiza por hitos y fases funcionales, sin fechas fijas de calendario:

```
[Fase 1: Núcleo y Desktop] ──► [Fase 2: Móvil y TV] ──► [Fase 3: Emparejamiento LAN] ──► [Fase 4: Smart TV e iOS] ──► [Fase 5: Funciones Avanzadas]
```

### 📍 Fase 1 — Núcleo del Sistema y MVP de Escritorio
- [x] Parser en streaming de M3U/M3U8 con suite de tests basada en *golden files*.
- [x] Parser de guía EPG (XMLTV) con soporte de compresión `.xml.gz`.
- [x] Cliente para la API de Xtream Codes (Directo, Películas y Series).
- [x] Base de datos Drift (SQLite) con motor de búsqueda instantánea FTS5.
- [x] Aplicación de escritorio para Windows y Linux con `media_kit` (libmpv).
- [x] Empaquetado instalable para Windows (Inno Setup) y Linux (.deb y portable).

### 📍 Fase 2 — Experiencia Móvil y Smart TV (10-Foot UI)
- [x] Interfaz `TvShell` de 10 pies con soporte integral para mando a distancia D-pad.
- [x] Motor de reproducción Media3 (ExoPlayer) para Android y Android TV.
- [x] Interfaz táctil ergonómica `MobileShell` con gestos y Picture-in-Picture.
- [x] Rejilla interactiva de programación EPG y teclado virtual para TV.
- [x] Detalle de contenido con carátulas, fondos y navegación de temporadas.

### 📍 Fase 3 — Emparejamiento Serverless y Sincronización Local
- [x] Flujo de onboarding en TV mediante código QR y PIN de 6 dígitos.
- [x] Canal de transferencia local seguro sobre WebSockets cifrados.
- [x] Motor de sincronización sin conflictos (*Last-Write-Wins* con *tombstones*).
- [ ] Descubrimiento automático en segundo plano de dispositivos emparejados en la misma red Wi-Fi.
- [ ] Copias de seguridad locales cifradas (exportar/importar archivo).

### 📍 Fase 4 — Optimización en Smart TVs y Expansión de Ecosistema
- [ ] Paquete optimizado para LG webOS (perfil de aceleración CanvasKit 720p).
- [ ] Exploración y soporte de Samsung Tizen (`flutter-tizen`).
- [ ] Versión de escritorio para Apple macOS.
- [ ] Aplicación para iOS / iPadOS con motor AVPlayer y permisos de red local.

### 📍 Fase 5 — Funciones Avanzadas para Usuarios Exigentes
- [ ] Selector avanzado de pistas de audio y sincronización manual de subtítulos.
- [ ] Modo multipantalla / Picture-in-Picture multivista.
- [ ] Control parental con bloqueo de canales y categorías mediante PIN.
- [ ] Soporte de nuevos idiomas comunitarios (francés, portugués, alemán, italiano).

---

## Cómo Contribuir

¡Agradecemos enormemente cualquier contribución, reporte de fallos y pull requests!

1. Haz un **Fork del repositorio** (`https://github.com/Stones-Dev/Rulbi`).
2. Crea una rama para tu funcionalidad: `git checkout -b feat/nueva-funcionalidad`.
3. **Escribe pruebas**: Si corriges un problema de importación o parsing, añade un archivo de prueba real (*golden file*) en `packages/protocols/test/fixtures/`.
4. Respeta el formato de [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `docs:`, `chore:`).
5. Verifica que los tests y el análisis pasan: `melos run analyze && melos run test`.
6. Abre una **Pull Request**.

---

## Licencia

Rulbi es un proyecto de código abierto. Sus módulos de dominio, protocolos, datos, tokens y emparejamiento están publicados bajo licencias permisivas (**MIT / BSD-3-Clause**), mientras que el reproductor de escritorio enlaza dinámicamente con libmpv bajo licencia **LGPL-2.1+ / LGPL-3.0**, asegurando la libertad total de uso y desarrollo de la plataforma.
