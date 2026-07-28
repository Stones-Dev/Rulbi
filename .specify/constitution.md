# Constitution — Principios rectores del proyecto

> Espejo de `02-Proyectos/Reproductor IPTV Multiplataforma/constitution.md` en el vault. Ver `.specify/README.md` para la regla de sincronización.

Estos principios gobiernan todas las decisiones del proyecto. Ante un conflicto entre conveniencia y principio, gana el principio; si un principio debe romperse, se documenta en un ADR.

## P1 — Rendimiento como requisito funcional

La razón de ser del proyecto es que las alternativas "no listan bien". Presupuestos de rendimiento no negociables: importar una lista de 100.000 canales sin congelar la UI; búsqueda con resultados en < 100 ms; arranque en frío < 3 s en una TV de gama baja; scroll fluido en listas virtualizadas. Todo parsing pesado (M3U, XMLTV) se ejecuta fuera del hilo de UI y en streaming, nunca cargando el archivo completo en memoria.

## P2 — Una base de código, tres experiencias

Un único codebase Flutter, pero con tres layouts de presentación deliberados: **10-foot UI** (TV, navegación por D-pad y foco visible), **touch** (móvil) y **desktop** (teclado/ratón, atajos). Compartir lógica jamás justifica una UI de móvil estirada en un televisor.

## P3 — Local-first

Todo funciona sin cuenta, sin conexión al backend y sin telemetría. La sincronización es una capa opcional que el usuario activa; nunca una condición de uso. Los datos del usuario viven primero en su dispositivo (SQLite) y el servidor es una réplica de conveniencia.

## P4 — Neutralidad de contenido

La aplicación no incluye, sugiere, promociona ni facilita contenido: es un reproductor genérico de listas que el usuario aporta. Este principio es además condición de supervivencia en App Store, Google Play y LG Content Store, cuyas políticas expulsan a los reproductores IPTV que insinúan acceso a contenido.

## P5 — Privacidad por defecto

Credenciales Xtream cifradas en reposo con el almacén seguro de cada plataforma (Keychain / Keystore / equivalente). Sin analítica de terceros en v1; si en el futuro se añade crash reporting o métricas, serán opt-in y se documentará en un ADR.

## P6 — El dominio no conoce al reproductor

Toda reproducción pasa por una abstracción (`PlayerPort`). Ningún módulo de dominio o de datos importa media3, mpv, AVPlayer ni API alguna de plataforma. Esto permite cambiar de motor por plataforma (o por decisión de licencia, ver P8) sin tocar el resto del sistema.

## P7 — Calidad verificable

Los parsers (M3U, XMLTV) y el cliente Xtream se desarrollan con TDD contra una batería de *golden files* reales, incluidos casos rotos y dialectos de paneles no estándar. CI en GitHub Actions compila y testea en cada push para todas las plataformas P1. Un bug de importación reportado se convierte en un golden file antes de arreglarse.

## P8 — No hipotecar el modelo de negocio

Mientras la decisión open source / comercial (D2) esté abierta, el núcleo y las apps evitan dependencias **GPL** que obligarían a liberar el código. Se prefieren componentes Apache-2.0 / MIT / LGPL (media3, AVPlayer, libVLC). Si se adopta un componente GPL (p. ej. libmpv en escritorio), se aísla y se registra el compromiso en un ADR con plan de salida.

## P9 — La TV es ciudadana de primera

El control por mando (D-pad, back, ok) y el foco visible se diseñan y prueban desde la primera pantalla, no como adaptación posterior. Toda pantalla nueva debe ser operable íntegramente sin ratón ni táctil.

## P10 — Documentación viva

Decisiones → ADRs (MADR). Estado entre sesiones → handoff (protocolo 12). Comprensión del código → grafo Graphify regenerado tras cambios relevantes y enlazado al vault. El repo mantiene sus artefactos SDD en `.specify/` sincronizados con esta carpeta.
