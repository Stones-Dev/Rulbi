#!/usr/bin/env bash
# Arranca el servidor Xtream de pruebas sin Docker (S7, incidencia menor de
# la verificación E2E: Docker Desktop no siempre está arriba cuando hace
# falta un ciclo rápido). Sigue siendo la vía secundaria — `docker compose
# -f docker-compose.dev.yml up --build` (ver README.md) es la soportada de
# verdad y la que usa CI/las capturas de verificación; este script es
# comodidad de desarrollo local, no un sustituto con la misma cobertura.
#
# NO probado de extremo a extremo (S7): esta máquina de desarrollo no tenía
# ffmpeg instalado, así que `make-fixtures.sh` nunca llegó a ejecutarse
# aquí. Lo que sí está verificado: `serve.py` acepta XTREAM_MEDIA_ROOT/
# XTREAM_IMAGES_ROOT (antes hardcodeaba /media e /images, rutas absolutas
# Unix que en Windows nativo resolverían contra la raíz de la unidad
# actual) y sigue sirviendo igual con Docker (docker-compose.dev.yml no
# fija esas variables, así que cae a los valores por defecto /media e
# /images de siempre). Si al ejecutar este script `make-fixtures.sh` falla
# por el `fontfile` de DejaVu (hardcodeado a la ruta de Debian), instala
# `fonts-dejavu-core` o ajusta esa ruta — no se ha podido reproducir ese
# paso aquí para dejarlo resuelto de antemano.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
RUN_DIR="$HERE/.local-run"
MEDIA_DIR="$RUN_DIR/media"
IMAGES_DIR="$RUN_DIR/images"

# --- Prerrequisitos: fallar rápido y explícito, no a mitad de fixtures ---
command -v ffmpeg >/dev/null 2>&1 || {
  echo "ERROR: falta ffmpeg (genera los vídeos/audio sintéticos de prueba)." >&2
  echo "Instálalo y vuelve a intentar; con Docker (README.md) no hace falta en el host." >&2
  exit 1
}

PYTHON_BIN="${PYTHON_BIN:-}"
if [ -z "$PYTHON_BIN" ]; then
  if command -v python >/dev/null 2>&1 && python --version >/dev/null 2>&1; then
    PYTHON_BIN=python
  elif command -v python3 >/dev/null 2>&1 && python3 --version >/dev/null 2>&1; then
    PYTHON_BIN=python3
  else
    echo "ERROR: no se encontró un Python real (ni 'python' ni 'python3' responden a --version)." >&2
    echo "En Windows, el alias de la Microsoft Store cuenta como 'no encontrado' para este check." >&2
    exit 1
  fi
fi

# --- Dependencia Python (versión fijada, igual que el Dockerfile) ---
"$PYTHON_BIN" -m pip show xtreamcodeserver 2>/dev/null | grep -q "Version: 1.1.0" \
  || "$PYTHON_BIN" -m pip install --quiet xtreamcodeserver==1.1.0

# --- Fixtures de vídeo/audio/subtítulos (idempotente: se saltan si ya existen) ---
if [ ! -f "$MEDIA_DIR/vod/movie.mp4" ]; then
  mkdir -p "$MEDIA_DIR"
  echo "Generando fixtures sintéticas en $MEDIA_DIR (puede tardar un minuto)..."
  bash "$HERE/make-fixtures.sh" "$MEDIA_DIR"
else
  echo "Fixtures ya generadas en $MEDIA_DIR — omitiendo make-fixtures.sh."
fi

# --- Imágenes estáticas (mismo origen que copia el Dockerfile) ---
mkdir -p "$IMAGES_DIR"
for asset in tv_cards posters backdrops episodes; do
  src="$REPO_ROOT/docs/design-assets/$asset"
  dst="$IMAGES_DIR/$asset"
  if [ -d "$src" ] && [ ! -d "$dst" ]; then
    cp -r "$src" "$dst"
  fi
done

echo "Arrancando servidor Xtream de pruebas (Ctrl+C para parar)..."
export XTREAM_MEDIA_ROOT="$MEDIA_DIR"
export XTREAM_IMAGES_ROOT="$IMAGES_DIR"
exec "$PYTHON_BIN" "$HERE/serve.py"
