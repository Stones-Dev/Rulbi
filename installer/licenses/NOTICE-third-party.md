# Avisos de terceros — componentes de reproducción de escritorio

Este directorio se distribuye junto al ejecutable de IPTV Player en Windows
(`installer/windows/build-installer.ps1` lo copia a `licenses/`) y en Linux
(`installer/linux/build-deb.sh` lo copia a
`/usr/share/doc/iptv-player/`).

## libmpv / mpv (LGPL 2.1)

`packages/player` usa [`media_kit`](https://pub.dev/packages/media_kit) como
implementación de `PlayerPort` en Windows y Linux (ADR-009). `media_kit` se
apoya en `libmpv`, compilado explícitamente en modo **LGPL** (no GPL):
`-Dgpl=false` + `--disable-gpl --disable-nonfree` (verificado en el spike de
S3 contra las fuentes de compilación de
[`media-kit/libmpv-win32-video-build`](https://github.com/media-kit/libmpv-win32-video-build)).

- Texto completo de la licencia: [`LGPL-2.1.txt`](./LGPL-2.1.txt).
- Copyright: mpv contributors — <https://mpv.io/>.
- **Windows**: `media_kit_libs_windows_video` empaqueta `libmpv-2.dll` (28.4 MB)
  dentro del instalador. El enlace es **dinámico** (la app carga la DLL en
  runtime, no la enlaza estáticamente) — esa es la condición que la §6 de la
  LGPL exige para poder distribuir la app bajo licencia propietaria, y la que
  ADR-009 se compromete a mantener en cualquier build futuro.
- **Linux**: `media_kit_libs_linux` **no empaqueta ningún binario**. Enlaza en
  runtime contra el `libmpv.so` del sistema (paquete `libmpv2` o `libmpv1`
  según la distro), que el `.deb` declara como dependencia
  (`Depends: libmpv2 | libmpv1`) en vez de distribuirlo.
- **Obligación de mantenimiento (ADR-009)**: cualquier actualización de
  `media_kit_libs_windows_video` / `media_kit_libs_linux` debe reverificar que
  el build upstream de `libmpv` sigue usando `-Dgpl=false` /
  `--disable-gpl --disable-nonfree` antes de adoptar la nueva versión. Un
  cambio silencioso de esas flags reintroduciría GPL sin que el proyecto lo
  note si no se revisa.

## FFmpeg (LGPL, vía libmpv)

`libmpv` enlaza a su vez contra FFmpeg. El mismo build LGPL (`-Dgpl=false`)
aplica también a los componentes de FFmpeg que arrastra — ver
[ffmpeg.org/legal.html](https://ffmpeg.org/legal.html) para el desglose
exacto de qué módulos quedan fuera al compilar sin GPL/nonfree.

## Resto de dependencias

El resto de dependencias directas del árbol de `apps/app` y `packages/player`
son Apache-2.0/MIT/BSD-3 (P8, `constitution.md`) y no generan obligación de
distribuir avisos aparte de las que ya cumplen sus propios repositorios en
pub.dev. Este NOTICE cubre específicamente los componentes con licencia
copyleft débil (LGPL), que son los que imponen obligaciones al empaquetar un
binario cerrado.
