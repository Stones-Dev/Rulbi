# Spec — Qué y por qué

> Espejo de `02-Proyectos/Reproductor IPTV Multiplataforma/spec.md` (rev. 1.1) en el vault. Ver `.specify/README.md` para la regla de sincronización.

Especifica el producto sin hablar de tecnología (el *cómo* está en `plan.md`; las pantallas, en `ui-spec.md`).

## Problema

Los usuarios de IPTV manejan listas M3U o cuentas Xtream de proveedores muy heterogéneos. Los reproductores existentes fallan de tres maneras recurrentes: (1) importan mal o lento las listas grandes, (2) presentan las categorías y la guía de forma pobre o rota, y (3) no existen o funcionan mal en televisores, que es donde realmente se consume la TV. Además, quien usa varios dispositivos tiene que reconfigurar todo en cada uno — y teclear credenciales con un mando a distancia es una tortura.

## Usuarios objetivo

- **Persona A — "El del salón"**: consume en su LG webOS o Android TV/Fire TV con mando. Quiere zapear, guía y favoritos, cero fricción.
- **Persona B — "El multi-dispositivo"**: configura en el móvil o PC, ve en la TV. Quiere pasar su configuración a la TV en segundos y que favoritos y progreso se mantengan coherentes en casa.
- **Persona C — "El técnico"**: varias fuentes, listas de 50k+ canales, exige velocidad de importación y búsqueda. Valora que sus credenciales no salgan de su casa.

## Historias de usuario

**HU-01 · Importar M3U** — Como usuario quiero añadir una fuente M3U (archivo local o URL) y ver mis canales agrupados por categorías, con logo y nombre correctos.
*Aceptación*: una lista de 100k entradas importa con indicador de progreso y sin congelar la UI; los atributos `group-title`, `tvg-logo`, `tvg-id` se respetan; las entradas malformadas se omiten con aviso resumido, nunca abortan la importación completa.

**HU-02 · Conectar Xtream** — Como usuario quiero introducir host, usuario y contraseña de mi panel Xtream y obtener live, películas y series organizadas.
*Aceptación*: se distinguen los tres tipos de contenido; las credenciales se guardan cifradas; "probar conexión" informa del estado y caducidad de la cuenta antes de guardar; los errores del panel producen mensajes claros, no pantallas vacías.

**HU-03 · Guía EPG** — Como usuario quiero ver qué se emite ahora y después en cada canal, y una rejilla de programación navegable.
*Aceptación*: EPG por URL XMLTV (con soporte .gz) o del propio panel Xtream; emparejamiento por `tvg-id`; la rejilla carga solo la ventana temporal visible; un EPG de cientos de MB no bloquea la app.

**HU-04 · Búsqueda instantánea** — Como usuario quiero buscar por nombre entre todos mis canales y VOD y ver resultados mientras escribo.
*Aceptación*: resultados < 100 ms con 100k canales; insensible a acentos y mayúsculas; en TV, teclado en pantalla operable con D-pad.

**HU-05 · Favoritos** — Como usuario quiero marcar canales como favoritos y verlos en una sección propia, en el orden que yo decida.

**HU-06 · Reproducción adaptada al dispositivo** — Como usuario quiero reproducir cualquier canal o VOD con controles adecuados: mando en TV (zapping con flechas, overlay con OK), táctil en móvil (gestos, PiP), teclado/ratón en escritorio (atajos).
*Aceptación*: formatos mínimos HLS, MPEG-TS sobre HTTP, MP4/MKV; cambio de canal percibido < 2 s sobre una conexión sana; detalle por shell en `ui-spec.md` §2.13.

**HU-07 · Multi-fuente** — Como usuario quiero varias fuentes activas a la vez, refrescarlas bajo demanda y activarlas/desactivarlas sin borrar su configuración.

**HU-08 · Enviar mi configuración a otro dispositivo (sin cuentas ni nube)** — Como usuario quiero configurar todo cómodamente en el móvil o el PC y pasarlo a la TV en segundos, sin crear cuentas ni depender de servidores.
*Aceptación*: la TV (u otro receptor) muestra un **código QR y un código de 6 dígitos**; desde el móvil, escaneo el QR con la cámara **o** tecleo el código de 6 dígitos, elijo qué enviar (fuentes, favoritos, progreso, ajustes) y la transferencia ocurre por la red local; las credenciales nunca aparecen dentro del QR ni salen de la red doméstica; si la red bloquea el descubrimiento automático, el QR sigue funcionando (incluye la dirección) y existe entrada manual de IP como último recurso.

**HU-09 · Sincronización automática en casa (premium)** — Como usuario quiero que mis dispositivos ya emparejados se mantengan al día solos cuando coinciden en la misma Wi-Fi.
*Aceptación*: con la opción activada por dispositivo, favoritos, fuentes y progreso convergen sin intervención al abrir la app en la misma red; los conflictos se resuelven de forma predecible (gana el cambio más reciente); todo funciona igual de bien con la opción apagada.

**HU-10 · Continuar viendo** — Como usuario quiero retomar películas y episodios donde los dejé, con el siguiente episodio sugerido en series.

## Requisitos no funcionales

- **RNF-01 Rendimiento**: presupuestos de P1 de la constitution.
- **RNF-02 Robustez de importación**: ninguna entrada malformada aborta una importación; todo fallo de parsing queda registrado y reproducible como golden file.
- **RNF-03 Offline**: sin red, la app abre y muestra los datos ya importados.
- **RNF-04 Huella en TV**: memoria compatible con TVs de gama baja (objetivo < 300 MB en uso normal).
- **RNF-05 Privacidad**: P5 de la constitution; además, por ADR-002 (Sincronización serverless por emparejamiento local), ningún dato del usuario se almacena en servidores del proyecto.
- **RNF-06 i18n**: textos localizables desde v1 (idiomas concretos: D4).
- **RNF-07 Emparejamiento**: mostrar QR/código funciona en todos los shells; escanear QR solo se ofrece donde hay cámara (móvil); el flujo por código es 100 % operable con D-pad.

- **RNF-08 Accesibilidad**: toda pantalla operable al 100 % con D-pad o teclado; foco siempre visible y de alto contraste; compatibilidad con lectores de pantalla (TalkBack / VoiceOver) en móvil; contraste mínimo WCAG AA; tipografía escalable.
- **RNF-09 Simplicidad para no técnicos**: lenguaje claro sin jerga en toda la UI (nada de "upsert", "FTS" ni "mDNS" de cara al usuario); onboarding en 3 pasos o menos; valores por defecto sensatos que funcionen sin tocar ajustes; todo error muestra una acción sugerida, no un código.
- **RNF-10 Calidad de audio**: selección de pista de audio y subtítulos en todas las plataformas; sonido multicanal y passthrough (AC3/EAC3) donde la plataforma lo permita — relevante en TV boxes conectadas por HDMI a equipos de sonido (validar alcance real en spikes S1–S4).

## Clarificaciones

**Resueltas (2026-07-20, con el usuario):**
1. Alcance v1 = M3U + EPG + Xtream + transferencia/sync entre dispositivos. DVR fuera de v1.
2. TVs prioritarias: Android TV / Fire TV y LG webOS. Tizen y Apple TV, a v2.
3. Modelo de negocio: sin decidir → principio P8 (evitar GPL en el núcleo) y gate D2 en Fase 2.
4. **Sincronización: serverless.** Sin backend ni cuentas en v1; emparejamiento QR/código + transferencia y sync por red local (ADR-002). La sync LAN automática se posiciona como rasgo premium.

**Abiertas:**
- C1 · Nombre del producto (D1).
- C2 · Licencia/modelo (D2) — gate de Fase 2.
- C3 · Idiomas v1 (D4) — durante Fase 1.
- C4 · Si "premium" implica pago: qué funciones exactas son de pago y mecanismo (compra única vs suscripción) — depende de D2.

## Fuera de alcance de v1 (recordatorio)

**iOS queda fuera de la v1** (aplazado a v1.1 por falta de Mac disponible para compilar/firmar con Xcode — restricción de recursos, no de producto ni arquitectura; ver `plan.md` revisión 1.2). Nada de este documento cambia por ello: las historias de usuario aplican igual a iOS cuando se retome.
