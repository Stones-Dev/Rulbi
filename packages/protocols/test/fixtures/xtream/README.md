# Fixtures Xtream — T1.1

Dumps JSON reales de `player_api.php` para el cliente Xtream
(`packages/protocols`), capturados el 2026-07-29 contra un servidor Xtream
Codes API open source **corriendo en local**, sin ningún panel comercial ni
credenciales reales de por medio (principio P4: neutralidad de contenido —
nunca se ha tocado una URL, usuario o contraseña de un proveedor real).

## Corrección respecto al encargo original

El encargo original citaba `Divarion-D/xtream_api` como fuente primaria.
**Ese repositorio no existe** (confirmado 404 en GitHub y ausente en la
búsqueda de repos de GitHub, 2026-07-29). `o0Zz/xtreamcodeserver` — que el
encargo trataba como plan B "si sobra tiempo" — pasa a ser la **única**
fuente de dialecto Xtream de esta tarea.

Se buscó un segundo servidor Xtream API open source real para tener un
segundo dialecto de comparación, sin éxito: los únicos resultados eran
*bridges* que reexponen contenido de streaming real de terceros (Vavoo,
Jellyfin, AceStream) vía la API Xtream — se descartaron explícitamente por
P4, ya que levantarlos implicaría tocar (aunque sea en pruebas) un catálogo
de contenido real. Si en T1.4 hace falta un segundo dialecto de comparación,
la vía razonable es documentación pública de la API Xtream Codes
(`xtream-ui.org`) en vez de un segundo servidor.

## Fuente: `o0Zz/xtreamcodeserver`

- Repo: https://github.com/o0Zz/xtreamcodeserver (MIT, 6 estrellas en el
  momento de la captura — proyecto pequeño, ver "Limitación conocida" abajo).
- Paquete PyPI `xtreamcodeserver` (versión 1.1.0), instalado con
  `pip install xtreamcodeserver`.
- Levantado localmente en `127.0.0.1:8081`, credenciales `test`/`test`,
  poblado con datos **ficticios en memoria** (`XTreamCodeMemoryStream`, sin
  vídeo real: 1 categoría live con 2 canales, 1 categoría VOD con 1 película,
  1 categoría de series con 1 serie/1 temporada/2 episodios — todo con
  nombres, sinopsis y reparto de relleno, sin licencia de contenido
  implicada). El servidor se apaga al terminar la captura.

## `dialect_o0zz/` — las 9 actions pedidas

| Fichero | Action / llamada | Contenido |
|---|---|---|
| `auth.json` | `player_api.php?username=&password=` (sin `action=`) | Respuesta base `user_info`/`server_info` — el equivalente a la autenticación inicial de un cliente Xtream real. |
| `get_live_categories.json` | `action=get_live_categories` | 1 categoría ("Noticias"). |
| `get_vod_categories.json` | `action=get_vod_categories` | 1 categoría ("Peliculas"). |
| `get_series_categories.json` | `action=get_series_categories` | 1 categoría ("Series"). |
| `get_live_streams.json` | `action=get_live_streams` | 2 canales live, con `epg_channel_id`, `category_id`, `tv_archive`. |
| `get_vod_streams.json` | `action=get_vod_streams` | 1 película, con `container_extension`, `rating_5based`. |
| `get_series.json` | `action=get_series` | 1 serie (metadatos de listado, sin temporadas/episodios expandidos). |
| `get_series_info.json` | `action=get_series_info&series_id=...` | La misma serie con temporadas y episodios expandidos (estructura anidada `seasons`/`episodes`). |
| `get_vod_info.json` | `action=get_vod_info&vod_id=...` | Ficha completa de la película (`info` + `movie_data`, director/reparto/género de relleno). |

## Limitación conocida

`o0Zz/xtreamcodeserver` es una librería de terceros de uso reducido (6
estrellas). Su JSON reproduce fielmente la forma documentada de la API
Xtream Codes (`get.php`/`player_api.php`, ver `xtream-ui.org`), pero no está
garantizado que capture **todas** las peculiaridades/campos extra que
paneles Xtream de producción reales añaden fuera de la especificación (los
propios paneles comerciales varían bastante entre sí — es justo el problema
que T1.4 tiene que resolver con tolerancia a dialectos). Si durante T1.4
aparecen discrepancias con respuestas reales reportadas por el usuario, se
añaden como fixtures nuevos siguiendo el principio P7 (bug de importación →
golden file primero), no se reemplaza este dumps base.
