#!/usr/bin/env bash
#
# Clona /repo (bind-mount de solo lectura de la raíz del repo en el host) a
# /work dentro del contenedor, y corre el mismo camino que el job
# `linux-package` de package-desktop.yml: melos bootstrap -> codegen drift ->
# gen-l10n -> flutter build linux --release -> installer/linux/build-deb.sh.

set -euo pipefail

if [[ ! -d /repo ]]; then
  echo "Monta el repo en /repo (ver docstring de Dockerfile.linux-build)." >&2
  exit 1
fi

echo "== Copiando /repo -> /work (rsync: incluye cambios sin commitear; evita symlinks de melos sobre un bind-mount de Windows) =="
mkdir -p /work
rsync -a --delete \
  --exclude='.git' \
  --exclude='build/' \
  --exclude='.dart_tool/' \
  --exclude='dist/' \
  /repo/ /work/
cd /work

VERSION="$(grep -m1 '^version:' apps/app/pubspec.yaml | sed -E 's/version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+).*/\1/')"
echo "Versión detectada: $VERSION"

echo "== melos bootstrap =="
dart pub global activate melos
export PATH="$PATH:/root/.pub-cache/bin"
melos bootstrap

echo "== packages/data — pub get + codegen drift =="
pushd packages/data >/dev/null
flutter pub get
dart run build_runner build --delete-conflicting-outputs
popd >/dev/null

echo "== apps/app — gen-l10n + build linux --release =="
pushd apps/app >/dev/null
flutter gen-l10n
flutter build linux --release
popd >/dev/null

BUNDLE_DIR="/work/apps/app/build/linux/x64/release/bundle"
OUTPUT_DIR="/dist"
mkdir -p "$OUTPUT_DIR"

echo "== installer/linux/build-deb.sh =="
bash installer/linux/build-deb.sh "$VERSION" "$BUNDLE_DIR" "$OUTPUT_DIR"

echo
echo "== Verificación =="
DEB_FILE="$OUTPUT_DIR/iptv-player_${VERSION}_amd64.deb"

echo "--- dpkg-deb -I (metadata, confirma el campo Depends) ---"
dpkg-deb -I "$DEB_FILE"

echo "--- dpkg-deb -c (primeras 20 líneas del layout) ---"
# `| head -20` directo revienta bajo `set -o pipefail`: head cierra el pipe
# en cuanto tiene sus 20 líneas y dpkg-deb recibe SIGPIPE, que pipefail lee
# como fallo del propio dpkg-deb aunque el .deb esté perfectamente bien
# (encontrado en una corrida real: RUN_EXIT=2 con ambos artefactos ya
# generados y correctos). Se materializa el listado completo primero y
# se recorta después, fuera del pipe.
dpkg-deb -c "$DEB_FILE" > /tmp/deb-listing.txt
head -20 /tmp/deb-listing.txt

echo "--- ldd sobre los binarios del bundle (busca el enlace dinámico a libmpv) ---"
found_mpv=0
while IFS= read -r -d '' f; do
  if ldd "$f" 2>/dev/null | grep -qi mpv; then
    echo "$f:"
    ldd "$f" | grep -i mpv
    found_mpv=1
  fi
done < <(find "$BUNDLE_DIR" -type f \( -name "*.so*" -o -name "iptv_app" \) -print0)
if [[ "$found_mpv" -eq 0 ]]; then
  echo "AVISO: ningún binario del bundle referencia libmpv directamente vía ELF NEEDED." >&2
  echo "Puede que media_kit lo resuelva en runtime en vez de enlazarlo en compilación —" >&2
  echo "confírmalo contra docs/bench/S3-desktop-spike.md antes de asumir que es un fallo." >&2
fi

echo
echo "Artefactos en $OUTPUT_DIR:"
ls -lh "$OUTPUT_DIR"
