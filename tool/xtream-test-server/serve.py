"""Servidor Xtream de pruebas — Rulbi / IPTVapp, solo desarrollo.

Sirve un catálogo Xtream Codes enteramente sintético (generado por
make-fixtures.sh en build time) para verificar manualmente lo que S6 dejó
pendiente: selector de pistas de audio/subtítulos y seek de VOD/series.
Ningún vídeo real de ningún proveedor está involucrado (principio P4) — esto
no simula ni reemplaza un panel comercial, solo da algo real que reproducir.

Credenciales: test / test. Puerto: 8081.
"""

from __future__ import annotations

import http.server
import logging
import os
import threading
import time

from xtreamcodeserver.credentials.credentials import XTreamCodeCredentials
from xtreamcodeserver.entry.category import XTreamCodeCategory
from xtreamcodeserver.entry.entry import XTreamCodeType
from xtreamcodeserver.entry.live import XTreamCodeLive
from xtreamcodeserver.entry.serie import XTreamCodeSerie
from xtreamcodeserver.entry.serie_episode import XTreamCodeEpisode
from xtreamcodeserver.entry.serie_season import XTreamCodeSeason
from xtreamcodeserver.entry.vod import XTreamCodeVod
from xtreamcodeserver.providers.inmemory.credentials_provider import (
    XTreamCodeCredentialsMemoryProvider,
)
from xtreamcodeserver.providers.inmemory.entry_provider import (
    XTreamCodeEntryMemoryProvider,
)
from xtreamcodeserver.server import XTreamCodeServer
from xtreamcodeserver.stream.filesystemstream import XTreamCodeFileSystemStream

logging.basicConfig(level=logging.INFO)
_LOGGER = logging.getLogger(__name__)

MEDIA_ROOT = "/media"
IMAGES_ROOT = "/images"
LOGIN = "test"
PASSWORD = "test"
ADDR = "0.0.0.0"
PORT = 8081

# Servidor estático auxiliar (mismo proceso, hilo aparte) para
# cover_url/icon_url — S6.5, verificación visual de MediaCard contra el
# mismo arte ya fusionado en los frames canónicos de Figma (38:3). No es
# parte del protocolo Xtream real: xtreamcodeserver no expone un handler de
# estáticos, así que se sirve aparte en vez de forzarlo dentro del mock.
IMAGES_PORT = 8082
IMAGES_BASE_URL = f"http://127.0.0.1:{IMAGES_PORT}"


def _path(*parts: str) -> str:
    return os.path.join(MEDIA_ROOT, *parts)


def _image_url(*parts: str) -> str:
    return f"{IMAGES_BASE_URL}/{'/'.join(parts)}"


def _start_image_server() -> None:
    handler = lambda *a, **kw: http.server.SimpleHTTPRequestHandler(  # noqa: E731
        *a, directory=IMAGES_ROOT, **kw
    )
    httpd = http.server.ThreadingHTTPServer((ADDR, IMAGES_PORT), handler)
    thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    _LOGGER.info("Servidor de imágenes listo en %s (docs/design-assets/tv_cards+posters)", IMAGES_BASE_URL)


def build_catalog(entry_provider: XTreamCodeEntryMemoryProvider) -> None:
    """Catálogo con los títulos canónicos del frame Figma `38:3` (Desktop /
    Home), no genéricos — así una captura de la Home real es comparable 1:1
    contra el frame en vez de mostrar solo iconos de fallback (S6.5, Fase 2
    de la verificación visual). Construido a mano (no con el escáner de
    carpetas de la CLI) para que ids/extensiones/temporadas sean exactos y
    repetibles en cada arranque.

    `tv_card_*` (16:9) alimenta cover_url/icon_url porque son los assets
    pensados para las filas de Home (confirmado contra
    tool/render_refined_screen_mockups.py en el handoff del 08-17) — los
    pósters 2:3 de `docs/design-assets/posters/` no se usan aquí.
    """
    # --- Live: "Ahora en tus canales" (38:3 no tiene asset de canal en vivo
    # en 48:2 — el handoff del 08-17 lo deja explícito: "sin asset
    # equivalente" — así que estos 3 se quedan con el icono de fallback a
    # propósito, mismo que en el frame canónico) ---
    live_category = XTreamCodeCategory(name="Live sintético", category_type=XTreamCodeType.LIVE)
    for name in ("Canal 5 · Noticias", "DeporTV · Liga", "Cine Norte · Estreno"):
        live_category.add_entry(
            XTreamCodeLive(
                name=name,
                stream=XTreamCodeFileSystemStream(_path("live", "channel1.ts")),
            )
        )
    entry_provider.add_category(live_category)

    # --- VOD: "Continuar viendo" + "Favoritos", 4 títulos cada una (38:3) ---
    # Las 4 de "Continuar viendo" comparten el único fichero .mp4 real (con
    # pistas de audio/subs de S6) para no cuadruplicar el build de ffmpeg —
    # el propósito de esta fase es el arte de MediaCard, no más contenido
    # reproducible; seek/pistas ya están cubiertos por T6.
    continue_watching = ("el_faro_rojo", "dominio_norte", "cronos_s02", "via_muerta")
    favorites = ("umbra", "litoral", "sangre_fria", "8_bits")
    titles = {
        "el_faro_rojo": "El Faro Rojo",
        "dominio_norte": "Dominio Norte",
        "cronos_s02": "Cronos S02",
        "via_muerta": "Vía Muerta",
        "umbra": "Umbra",
        "litoral": "Litoral",
        "sangre_fria": "Sangre Fría",
        "8_bits": "8 Bits",
    }
    vod_category = XTreamCodeCategory(name="Películas sintéticas", category_type=XTreamCodeType.VOD)
    for slug in continue_watching + favorites:
        vod_category.add_entry(
            XTreamCodeVod(
                name=titles[slug],
                extension=".mp4",
                stream=XTreamCodeFileSystemStream(_path("vod", "movie.mp4")),
                cover_url=_image_url("tv_cards", f"tv_card_{slug}.jpg"),
                description="Contenido sintético (testsrc2 + tonos) para verificar selector de pistas y seek.",
            )
        )
    entry_provider.add_category(vod_category)

    # --- Series: Cronos S02, 2 temporadas x 2 episodios ---
    # >=2 episodios por temporada a propósito: hace falta poder distinguir
    # "Continuar T1E2" de una vuelta a T1E1. Sin arte de episodio propio en
    # el repo (docs/design-assets no trae cronos_epNN.*) — movie_image se
    # deja vacío a propósito, no se inventa un asset; XtreamEpisode.stillUrl
    # (paso 8) cae a su fallback, que es el comportamiento correcto sin él.
    series_category = XTreamCodeCategory(name="Series sintéticas", category_type=XTreamCodeType.SERIE)
    serie = XTreamCodeSerie(name="Cronos S02", cover_url=_image_url("tv_cards", "tv_card_cronos_s02.jpg"))
    for season_num in (1, 2):
        season = XTreamCodeSeason(
            season_number=season_num,
            name=f"Temporada {season_num}",
            cover_url=None,
            description=None,
        )
        for episode_num in (1, 2):
            season.add_episode(
                XTreamCodeEpisode(
                    episode_number=episode_num,
                    name=f"S{season_num:02d}E{episode_num:02d}",
                    extension=".mkv",
                    stream=XTreamCodeFileSystemStream(
                        _path("series", f"s{season_num:02d}e{episode_num:02d}.mkv")
                    ),
                )
            )
        serie.add_season(season)
    series_category.add_entry(serie)
    entry_provider.add_category(series_category)


def main() -> None:
    _start_image_server()

    credentials_provider = XTreamCodeCredentialsMemoryProvider()
    credentials_provider.add_or_update_credentials(XTreamCodeCredentials(LOGIN, PASSWORD))

    entry_provider = XTreamCodeEntryMemoryProvider()
    build_catalog(entry_provider)

    server = XTreamCodeServer(entry_provider, None, credentials_provider)
    server.setup(ADDR, PORT, None)

    _LOGGER.info(
        "Xtream test server listo — credenciales %s/%s, puerto %s (catálogo sintético, sin contenido real)",
        LOGIN,
        PASSWORD,
        PORT,
    )
    server.start()

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        pass

    server.stop()


if __name__ == "__main__":
    main()
