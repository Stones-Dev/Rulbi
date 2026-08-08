"""Servidor Xtream de pruebas — Rulbi / IPTVapp, solo desarrollo.

Sirve un catálogo Xtream Codes enteramente sintético (generado por
make-fixtures.sh en build time) para verificar manualmente lo que S6 dejó
pendiente: selector de pistas de audio/subtítulos y seek de VOD/series.
Ningún vídeo real de ningún proveedor está involucrado (principio P4) — esto
no simula ni reemplaza un panel comercial, solo da algo real que reproducir.

Credenciales: test / test. Puerto: 8081.
"""

from __future__ import annotations

import logging
import os
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
LOGIN = "test"
PASSWORD = "test"
ADDR = "0.0.0.0"
PORT = 8081


def _path(*parts: str) -> str:
    return os.path.join(MEDIA_ROOT, *parts)


def build_catalog(entry_provider: XTreamCodeEntryMemoryProvider) -> None:
    """Catálogo mínimo pero suficiente para cubrir lo pendiente de S6.

    Construido a mano (no con el escáner de carpetas de la CLI) para que
    ids, extensiones y numeración de temporada/episodio sean exactos y
    repetibles en cada arranque, en vez de depender de un regex sobre
    nombres de fichero.
    """
    # --- Live: 1 categoría, 1 canal ---
    live_category = XTreamCodeCategory(name="Live sintético", category_type=XTreamCodeType.LIVE)
    live_category.add_entry(
        XTreamCodeLive(
            name="Canal de prueba",
            stream=XTreamCodeFileSystemStream(_path("live", "channel1.ts")),
        )
    )
    entry_provider.add_category(live_category)

    # --- VOD: 1 categoría, 1 película (3 audios + 2 subs, ver make-fixtures.sh) ---
    vod_category = XTreamCodeCategory(name="Películas sintéticas", category_type=XTreamCodeType.VOD)
    vod_category.add_entry(
        XTreamCodeVod(
            name="Película de prueba",
            extension=".mp4",
            stream=XTreamCodeFileSystemStream(_path("vod", "movie.mp4")),
            description="Contenido sintético (testsrc2 + tonos) para verificar selector de pistas y seek.",
        )
    )
    entry_provider.add_category(vod_category)

    # --- Series: 1 categoría, 1 serie, 2 temporadas x 2 episodios ---
    # >=2 episodios por temporada a propósito: hace falta poder distinguir
    # "Continuar T1E2" de una vuelta a T1E1.
    series_category = XTreamCodeCategory(name="Series sintéticas", category_type=XTreamCodeType.SERIE)
    serie = XTreamCodeSerie(name="Serie de prueba")
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
