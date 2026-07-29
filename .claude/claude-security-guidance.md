# Threat model — Reproductor IPTV Multiplataforma

App cliente offline-first, sin backend ni cuentas (ADR-002). No hay servidor
propio: no busques vulnerabilidades de servidor web, busca las de un cliente que
consume datos no confiables y custodia credenciales locales.

## Activos a proteger

1. **Credenciales de panel Xtream** (usuario/contraseña) — deben vivir solo en
   Keychain/Keystore vía el puerto de almacén seguro de `packages/data`.
2. **URLs M3U que llevan credenciales embebidas** (`http://user:pass@host/...`,
   `get.php?username=…&password=…`) — mismo trato que 1.
3. **Token efímero de emparejamiento** (TTL 2 min, un solo uso, bloqueo tras 3
   intentos) y la **clave de sesión** derivada (X25519 → HKDF → AES-GCM).
4. Datos de catálogo y EPG: **no** son secretos. No los trates como tales.

## Reglas por paquete

### packages/pairing
- Todo material criptográfico se genera con `Random.secure()`. `Random()` en
  este paquete es un hallazgo, siempre.
- AES-GCM: nonce único por mensaje. Nonce constante, derivado del contador sin
  garantía de unicidad, o reutilizado entre sesiones → hallazgo crítico.
- Comparación de tokens/códigos/MACs en tiempo constante. `==` sobre bytes de
  autenticación es un hallazgo.
- No debilitar los límites del protocolo de sesión: TTL 2 min, un solo uso,
  bloqueo tras 3 intentos. Cualquier cambio que los relaje o los haga
  configurables hacia arriba merece ser señalado.
- Claves, tokens y códigos **nunca** en logs, en mensajes de excepción, ni en
  `toString()`.
- El export a fichero de `ConfigPackage` es por diseño **sin secretos**
  (ui-spec §3.2). Cualquier credencial que se cuele ahí es un hallazgo.
- Limitación **ya conocida y documentada** en el propio puerto: entropía del
  código de 6 dígitos, pendiente de ADR tras el spike S5. Es contexto, no
  permiso para ignorar hallazgos nuevos que la empeoren.

### packages/data
- Credenciales Xtream: al almacén seguro, jamás a una tabla drift, jamás al
  payload de sync LWW, jamás al export a fichero, jamás a un log.
- SQL: usar la API tipada de drift. SQL construido por interpolación de strings
  con entrada de usuario — en especial consultas `MATCH` de FTS5 desde la caja
  de búsqueda — es un hallazgo.

### packages/protocols
- **Todo lo que entra aquí es hostil**: listas M3U públicas, XMLTV de terceros,
  JSON de paneles Xtream desconocidos.
- Descompresión gzip de XMLTV: exige límite de ratio y de tamaño descomprimido.
  Un gunzip al vuelo sin tope es una bomba de descompresión (relevante para T1.3).
- Parser XML: DTD y entidades externas **deshabilitadas** (XXE / billion laughs).
- Nada de asignar buffers a partir de un campo de longitud controlado por el
  fichero de entrada.
- Fetch automático de una URL sacada de la propia lista = SSRF. Debe ser
  explícito y acotado, no un efecto colateral del parseo.
- Los fixtures de `packages/protocols/test/fixtures/` son públicos y por diseño
  no contienen credenciales reales. Una credencial ahí es un hallazgo real, no
  un dato de prueba.

### packages/player
- Las cabeceras de `#EXTVLCOPT`/`#KODIPROP` (User-Agent, Referer) vienen de la
  lista, o sea de un atacante: inyección CRLF en cabeceras HTTP.
- Es el único paquete donde se permite un SDK nativo de reproducción (P6).

## Patrones aprobados — reconócelos, no los reportes como bug

- `Channel.metadata` guarda atributos crudos no modelados como texto a
  propósito (incluido el fallback `#EXTBACKUP`/pipe). No es deserialización
  insegura.
- `ImportReport`/`DiscardedLine`: el parser **nunca** lanza excepción por una
  línea rota, la cuenta y la reporta (principio P7). No es tragarse errores en
  silencio.

## Nota

Este fichero se envía al modelo en cada revisión. **No contiene ni debe
contener secretos reales**, solo el modelo de amenazas.
