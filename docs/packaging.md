# Empaquetado de escritorio (beta) — Windows y Linux

S6 · Desktop III, tarea "Empaquetado beta". *Hecho cuando* (Notion): "Instalables
de Windows y Linux generados desde CI".

## Qué genera esto

| Plataforma | Formato | Script |
|---|---|---|
| Windows | Instalador Inno Setup, por usuario, sin firma | `installer/windows/build-installer.ps1` + `iptv-player.iss` |
| Linux | `.deb` (con `Depends: libmpv2 \| libmpv1`) + `.tar.gz` portable | `installer/linux/build-deb.sh` |

Decisiones y su porqué están en el ADR propuesto (pendiente de escribirse en
el vault por el chat de coordinación — ver `handoff.md`). Resumen rápido:

- **Windows → Inno Setup, no MSIX.** `windows-latest` ya trae Inno Setup 6
  preinstalado (coste de CI: cero). MSIX exigiría que quien prueba la beta
  importe un certificado autofirmado a mano — fricción que no tiene sentido
  para una beta privada. Ambos caminos parten del mismo
  `build\windows\x64\runner\Release`, así que elegir Inno ahora no cierra la
  puerta a MSIX en S19 (Microsoft Store).
- **Linux → `.deb`, no AppImage.** El problema real no es el formato, es que
  `media_kit_libs_linux` no empaqueta `libmpv` — enlaza dinámicamente contra
  el del sistema (spike S3, `docs/bench/S3-desktop-spike.md:423`). El `.deb`
  es el único formato que declara esa dependencia de forma que `apt` la
  resuelva. Un AppImage que además arrastrara `libmpv` habría sido el
  candidato número uno a romperse en CI (cierre de dependencias FFmpeg/glibc)
  sin aportar nada que S19 (Flathub/AUR) vaya a reutilizar.
- **Nombre "IPTV Player"**: placeholder deliberado — D1 (nombre comercial)
  sigue abierta. El identificador de aplicación permanente
  (`com.stonesdev.iptv`) no cambia en ningún sitio.
- **Sin firma de código.** Windows mostrará SmartScreen; el `.deb` no está
  firmado con GPG. Aceptado para esta fase — la firma real por canal es la
  tarea "Firma y empaquetado" de S19, no esta.

## Validar en local antes de tocar CI

El presupuesto de minutos de GitHub Actions de este repo (privado) es
limitado — ver la nota de coste en `handoff.md`. Los dos scripts de arriba
son **exactamente** los que ejecuta
`.github/workflows/package-desktop.yml`, así que probarlos en local antes de
hacer un `workflow_dispatch` prueba lo mismo que probaría CI, sin gastar
cuota.

### Windows (nativo)

```powershell
cd apps\app
flutter build windows --release
cd ..\..
.\installer\windows\build-installer.ps1 -AppVersion "0.1.0"
```

Sale `dist\windows\IPTVPlayer-0.1.0-beta-x64-setup.exe`. Instálalo, arranca
la app, reproduce algo contra el servidor Xtream de pruebas
(`tool/xtream-test-server/`), desinstala. El script falla solo si:
- no encuentra `vswhere.exe` / una instalación de Visual Studio,
- faltan `msvcp140.dll` / `vcruntime140.dll` / `vcruntime140_1.dll` en el
  redistribuible detectado,
- no encuentra `ISCC.exe` (Inno Setup 6 — <https://jrsoftware.org/isinfo.php>),
- el `.exe` resultante pesa menos de 20 MB (señal de que falta payload,
  típicamente `libmpv-2.dll`).

### Linux (Docker — no necesitas una máquina Linux)

```bash
docker build -f tool/packaging/Dockerfile.linux-build -t iptv-linux-build .
# MSYS_NO_PATHCONV=1 es necesario en Git Bash/MSYS en Windows: sin él, Git
# Bash reescribe "/repo" y "/dist" como si fueran rutas de Windows y el
# bind-mount se monta vacío (encontrado en la validación real de esta
# tarea — el contenedor arrancaba en verde pero /repo no existía dentro).
MSYS_NO_PATHCONV=1 docker run --rm \
  -v "$PWD:/repo:ro" -v "$PWD/dist/linux:/dist" \
  iptv-linux-build
```

El contenedor copia el repo internamente con `rsync` (no compila sobre el
bind-mount de Windows — `melos bootstrap` puede crear symlinks, y eso a
través del sistema de ficheros del host es una fuente de fallos ajena al
propio empaquetado; y no usa `git clone` porque eso solo traería el HEAD
comiteado, no los cambios en curso que es justo lo que esto valida). Corre
el mismo camino que el job `linux-package` de CI, y termina verificando:
- `dpkg-deb -I` — que `Depends: libmpv2 | libmpv1, libgtk-3-0` está bien,
- `dpkg-deb -c` — el layout del paquete,
- `ldd` sobre los binarios del bundle — busca la referencia a `libmpv`.

**Lo que esto NO verifica**: que la app arranque de verdad en Linux — el
contenedor no tiene servidor gráfico. Eso queda pendiente de una máquina
Linux real (o una VM con GUI). El contrato de Notion pide "build Linux", que
sí queda cubierto por esto.

**Validado de verdad (2026-08-08, esta sesión)**: `.deb` ~10 MB, `.tar.gz`
~13 MB. `ldd` confirma `libmpv.so.2` enlazado dinámicamente tanto en
`iptv_app` como en `libmedia_kit_video_plugin.so` — la obligación LGPL de
ADR-009 (enlace dinámico, no estático) se cumple de verdad, no solo sobre el
papel. Este intento también encontró y corrigió dos huecos reales que no se
habrían visto sin compilar el Linux build de verdad:
- **`libsecret-1-dev` faltaba** en la lista de dependencias de sistema —
  `ci.yml` nunca llama a `flutter build linux` (solo analyze/test), así que
  nadie había disparado el `pkg_check_modules(libsecret-1)` de
  `flutter_secure_storage_linux` hasta ahora. Añadido a
  `Dockerfile.linux-build` y a `package-desktop.yml`.
- **El umbral de tamaño mínimo estaba copiado de Windows** (20 MB, calibrado
  para `libmpv-2.dll`) y hacía fallar un `.deb`/`.tar.gz` perfectamente
  correctos, porque Linux no empaqueta `libmpv` (enlace dinámico contra el
  del sistema). Bajado a 8 MB, muy por debajo de lo medido (~10-13 MB) pero
  suficiente para atrapar un build vacío.

## Ejecutar el workflow de CI

Solo tras validar ambos en local:

```bash
gh workflow run package-desktop.yml -f platform=both
# o -f platform=windows / -f platform=linux para reintentar solo uno
```

Confirmar en verde con el patrón de `CLAUDE.md` (no basta con que `gh run
watch` termine sin error de shell):

```bash
gh run watch <run-id> --exit-status
gh run view <run-id> --json conclusion -q .conclusion   # debe imprimir: success
```

Descargar los artifacts (`gh run download <run-id>`) e instalar el `.exe`
**descargado de CI**, no el compilado en local — cierra el bucle de verdad,
no solo el de "el job terminó en verde".

## Avisos de licencia (LGPL, ADR-009)

El instalador de Windows distribuye `libmpv-2.dll` bajo LGPL 2.1. El `.deb`
no distribuye el binario (enlace dinámico contra el `libmpv` del sistema)
pero documenta la obligación igual. Textos en `installer/licenses/`:
- `LGPL-2.1.txt` — texto verbatim de la licencia (fuente:
  <https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt>).
- `NOTICE-third-party.md` — qué componente, qué obligación, y el compromiso
  de ADR-009 de reverificar `-Dgpl=false` en cada actualización de
  `media_kit_libs_*`.

## Deuda conocida, no resuelta aquí

- El prólogo (flutter-action → melos bootstrap → codegen drift → gen-l10n)
  está duplicado entre `ci.yml` y `package-desktop.yml` en vez de factorizado
  en una composite action. Deliberado: son pasos ya probados en verde
  docenas de veces, y no queríamos meter riesgo de refactor justo en el
  workflow que estrena la validación en CI real.
- No hay verificación de runtime en Linux (ver arriba) — pendiente de una
  máquina Linux física o virtual.
- El icono sigue siendo el de placeholder de Flutter en ambas plataformas —
  pendiente de D1 (nombre/marca).
- No hay mecanismo de auto-actualización para el instalador de `rulbi.com`
  — no estaba decidido en ningún ADR ni tarea antes de esta sesión, y sigue
  sin estarlo.
