#!/usr/bin/env bash
#
# Empaqueta la salida de `flutter build linux --release` en un .deb y un
# tar.gz. Mismo script en local (Docker, ver
# tool/packaging/Dockerfile.linux-build) y en CI
# (.github/workflows/package-desktop.yml) — la validación local solo vale si
# ambos caminos ejecutan literalmente esto.
#
# media_kit_libs_linux NO empaqueta libmpv (spike S3,
# docs/bench/S3-desktop-spike.md:423): enlaza dinámicamente contra el
# libmpv.so del sistema. El .deb es el único de los formatos considerados que
# declara esa dependencia de forma que algo la resuelva:
# `Depends: libmpv2 | libmpv1` — el `|` cubre Ubuntu 24.04 (libmpv2) y 22.04
# (libmpv1). Sin esto, `apt install ./iptv-player.deb` no arrastra libmpv y
# la app falla al arrancar en una máquina limpia.
#
# Compilado en ubuntu-latest (24.04): el binario queda atado a glibc 2.39+ y
# no correrá en distros más antiguas. Si algún día hace falta compatibilidad
# más amplia, se fija `runs-on: ubuntu-22.04` en el workflow — cambio de una
# línea, deliberadamente no hecho ahora.

set -euo pipefail

VERSION="${1:?Uso: build-deb.sh <version, p.ej. 0.1.0> <bundle_dir> <output_dir>}"
BUNDLE_DIR="${2:?falta bundle_dir (build/linux/x64/release/bundle)}"
OUTPUT_DIR="${3:?falta output_dir}"

if [[ ! -d "$BUNDLE_DIR" ]]; then
  echo "No existe '$BUNDLE_DIR' — ejecuta antes: flutter build linux --release (en apps/app)" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

PKG_NAME="iptv-player"
DEB_ARCH="amd64"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

INSTALL_DIR="$STAGE/opt/${PKG_NAME}"
mkdir -p "$INSTALL_DIR" "$STAGE/DEBIAN" \
  "$STAGE/usr/share/applications" \
  "$STAGE/usr/share/doc/${PKG_NAME}" \
  "$STAGE/usr/bin"

echo "== IPTV Player — empaquetado Linux (v${VERSION}) =="

cp -a "$BUNDLE_DIR"/. "$INSTALL_DIR/"

# Symlink en el PATH — convención FHS 3.0 §4.6 para paquetes bajo /opt.
ln -s "/opt/${PKG_NAME}/iptv_app" "$STAGE/usr/bin/${PKG_NAME}"

cp "$SCRIPT_DIR/iptv-player.desktop" "$STAGE/usr/share/applications/${PKG_NAME}.desktop"

# Avisos de licencia de terceros (LGPL — ADR-009). El enlace a libmpv.so es
# dinámico también aquí (nunca se empaqueta el binario), así que la
# obligación de ADR-009 ("enlace dinámico, no estático") se cumple por
# construcción — el aviso se documenta de todos modos.
cp "$REPO_ROOT/installer/licenses/LGPL-2.1.txt" "$STAGE/usr/share/doc/${PKG_NAME}/"
cp "$REPO_ROOT/installer/licenses/NOTICE-third-party.md" "$STAGE/usr/share/doc/${PKG_NAME}/"

cat > "$STAGE/usr/share/doc/${PKG_NAME}/copyright" <<'EOF'
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: IPTV Player
Source: https://rulbi.com

Files: *
Copyright: 2026 Stones Dev
License: proprietary
 Software propietario. Distribución beta privada — ver rulbi.com.

Files: libmpv.so* (enlazado en tiempo de ejecución vía el paquete del
 sistema libmpv2/libmpv1, no incluido en este paquete)
Copyright: mpv contributors
License: LGPL-2.1
 Ver LGPL-2.1.txt y NOTICE-third-party.md en este mismo directorio.
EOF

cat > "$STAGE/DEBIAN/control" <<EOF
Package: ${PKG_NAME}
Version: ${VERSION}
Section: video
Priority: optional
Architecture: ${DEB_ARCH}
Depends: libmpv2 | libmpv1, libgtk-3-0
Maintainer: Stones Dev <dev@rulbi.com>
Homepage: https://rulbi.com
Description: IPTV Player (beta)
 Reproductor IPTV multiplataforma. Build de beta privada — S6 Desktop III.
 Distribucion propia de respaldo (rulbi.com) junto a los canales oficiales.
EOF

# Permisos: directorios 0755, ficheros 0644, y el binario principal +x al
# final. Cubre opt/ Y usr/ — un primer intento solo tocaba opt/, dejando los
# ficheros de installer/licenses/ copiados a usr/share/doc/ con el 0755 que
# traían del checkout de Windows (detectado inspeccionando el .deb real con
# `dpkg-deb -c`, no a ojo).
find "$STAGE" -type d -exec chmod 0755 {} \;
find "$STAGE/opt" "$STAGE/usr" -type f -exec chmod 0644 {} \;
chmod 0755 "$INSTALL_DIR/iptv_app"
chmod 0644 "$STAGE/DEBIAN/control"

mkdir -p "$OUTPUT_DIR"

DEB_FILE="${OUTPUT_DIR}/${PKG_NAME}_${VERSION}_${DEB_ARCH}.deb"
dpkg-deb --build --root-owner-group "$STAGE" "$DEB_FILE"

TAR_FILE="${OUTPUT_DIR}/${PKG_NAME}-${VERSION}-linux-x64.tar.gz"
tar czf "$TAR_FILE" -C "$BUNDLE_DIR" .

echo "Generados:"
ls -lh "$DEB_FILE" "$TAR_FILE"

# A diferencia de Windows, aquí NO se empaqueta libmpv (enlace dinámico
# contra el del sistema — ver cabecera), así que el bundle es bastante más
# ligero: ~10 MB el .deb, ~12 MB el tar.gz, medido contra un build real
# (libflutter_linux_gtk.so + libapp.so + flutter_assets). El umbral no es el
# de Windows (20 MB, calibrado para libmpv-2.dll) — se fija muy por debajo de
# lo medido, solo para atrapar un build vacío o roto.
MIN_SIZE_MB=8
for f in "$DEB_FILE" "$TAR_FILE"; do
  size_mb=$(( $(stat -c%s "$f") / 1024 / 1024 ))
  if (( size_mb < MIN_SIZE_MB )); then
    echo "ERROR: '$f' pesa ${size_mb} MB, menos del umbral de ${MIN_SIZE_MB} MB." >&2
    exit 1
  fi
done

echo "OK: ${PKG_NAME} ${VERSION}"
