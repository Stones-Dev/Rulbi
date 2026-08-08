<#
.SYNOPSIS
    Empaqueta la salida de `flutter build windows --release` en un instalador
    Inno Setup. Mismo script en local y en CI
    (.github/workflows/package-desktop.yml) — la validación local solo vale
    si ambos caminos ejecutan literalmente esto.

.DESCRIPTION
    Dos cosas que `flutter build windows --release` NO deja listas y que este
    script resuelve antes de invocar ISCC.exe:

    1. El VC++ redistributable. La salida Release de Flutter no incluye
       msvcp140.dll / vcruntime140.dll / vcruntime140_1.dll. En una máquina
       con Visual Studio instalado la app arranca igual porque esas DLL ya
       están en el PATH/System32 del sistema; en un equipo limpio, no. Se
       copian desde el directorio Redist de la instalación de VS que detecta
       vswhere.exe (Microsoft permite redistribuirlas bajo el EULA del VC++
       Redistributable).
    2. Los avisos de licencia de terceros (LGPL — ADR-009, ver
       installer/licenses/). El instalador distribuye libmpv-2.dll.

.PARAMETER AppVersion
    Versión semver sin build number, ej. "0.1.0". Se usa tal cual en el
    AppVersion de Inno Setup y en el nombre del .exe de salida.

.PARAMETER OutputDir
    Carpeta donde queda el instalador final. Por defecto dist\windows en la
    raíz del repo.
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$AppVersion,

    [string]$OutputDir
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$AppDir = Join-Path $RepoRoot "apps\app"
$ReleaseDir = Join-Path $AppDir "build\windows\x64\runner\Release"

if (-not $OutputDir) {
    $OutputDir = Join-Path $RepoRoot "dist\windows"
}

if (-not (Test-Path $ReleaseDir)) {
    throw "No se encuentra $ReleaseDir`nEjecuta antes: flutter build windows --release (en apps/app)."
}

Write-Host "== IPTV Player — empaquetado Windows (v$AppVersion) ==" -ForegroundColor Cyan

# --- 1. Localizar y copiar el VC++ redistributable -------------------------
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) {
    throw "vswhere.exe no encontrado en '$vswhere' — instala Visual Studio o Build Tools."
}

$vsInstallPath = & $vswhere -latest -products * -property installationPath
if (-not $vsInstallPath) {
    throw "vswhere no encontró ninguna instalación de Visual Studio."
}
Write-Host "Visual Studio detectado en: $vsInstallPath"

$redistRoot = Join-Path $vsInstallPath "VC\Redist\MSVC"
if (-not (Test-Path $redistRoot)) {
    throw "No existe '$redistRoot' — falta el componente 'VC++ redistributable' en la instalación de VS."
}

$redistVersionDir = Get-ChildItem $redistRoot -Directory |
    Where-Object { $_.Name -match '^\d+\.\d+\.\d+' } |
    Sort-Object Name -Descending |
    Select-Object -First 1
if (-not $redistVersionDir) {
    throw "No se encontró ningún directorio de versión bajo '$redistRoot'."
}

$crtDir = Get-ChildItem (Join-Path $redistVersionDir.FullName "x64") -Directory |
    Where-Object { $_.Name -like "Microsoft.VC*.CRT" } |
    Select-Object -First 1 -ExpandProperty FullName
if (-not $crtDir -or -not (Test-Path $crtDir)) {
    throw "No se encontró el directorio del CRT redistribuible bajo '$($redistVersionDir.FullName)\x64'."
}
Write-Host "CRT redistribuible: $crtDir"

$requiredDlls = @("msvcp140.dll", "vcruntime140.dll", "vcruntime140_1.dll")
foreach ($dll in $requiredDlls) {
    $src = Join-Path $crtDir $dll
    if (-not (Test-Path $src)) {
        throw "Falta $dll en '$crtDir' — revisa el componente VC++ redistributable instalado."
    }
    Copy-Item $src -Destination $ReleaseDir -Force
    Write-Host "  copiado: $dll"
}

# --- 2. Avisos de licencia de terceros (LGPL, ADR-009) ----------------------
$licensesSrc = Join-Path $RepoRoot "installer\licenses"
$licensesDst = Join-Path $ReleaseDir "licenses"
New-Item -ItemType Directory -Force -Path $licensesDst | Out-Null
Copy-Item (Join-Path $licensesSrc "*") -Destination $licensesDst -Recurse -Force
Write-Host "Avisos de licencia copiados a: $licensesDst"

# --- 3. Compilar el instalador con Inno Setup -------------------------------
# Rutas candidatas, en orden: instalación de sistema (así lo trae
# windows-latest, ver runner-images) y las dos variantes de instalación por
# usuario que dejan winget/el instalador oficial cuando se corre sin admin
# (comprobado en esta máquina: winget lo dejó en LocalAppData\Programs).
$isccCandidates = @(
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles}\Inno Setup 6\ISCC.exe",
    "${env:LocalAppData}\Programs\Inno Setup 6\ISCC.exe"
)
$iscc = $isccCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) {
    throw "No se encuentra ISCC.exe (Inno Setup 6) en ninguna de: $($isccCandidates -join ', ')`n" +
          "Instálalo desde https://jrsoftware.org/isinfo.php (o `winget install JRSoftware.InnoSetup`).`n" +
          "En CI (windows-latest) ya viene preinstalado en la ruta de sistema — si esto falla ahí, es un cambio de imagen del runner."
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$issScript = Join-Path $PSScriptRoot "iptv-player.iss"
Write-Host "Compilando instalador con ISCC..."
& $iscc "/DMyAppVersion=$AppVersion" "/DMySourceDir=$ReleaseDir" "/DMyOutputDir=$OutputDir" $issScript

if ($LASTEXITCODE -ne 0) {
    throw "ISCC.exe terminó con código $LASTEXITCODE"
}

# --- 4. Verificar el resultado ----------------------------------------------
$installer = Get-ChildItem $OutputDir -Filter "*.exe" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if (-not $installer) {
    throw "ISCC.exe terminó en 0 pero no se encontró ningún .exe en '$OutputDir'."
}

$sizeMb = [math]::Round($installer.Length / 1MB, 1)
Write-Host "Instalador generado: $($installer.FullName) ($sizeMb MB)" -ForegroundColor Green

# libmpv-2.dll por sí sola pesa ~28 MB sin comprimir — si el instalador
# final pesa menos de esto, casi seguro falta payload (libmpv, flutter_assets).
$minSizeMb = 20
if ($sizeMb -lt $minSizeMb) {
    throw "El instalador pesa $sizeMb MB, menos del umbral de $minSizeMb MB — " +
          "probablemente falta libmpv-2.dll u otro payload. Revisa el build antes de distribuir esto."
}

Write-Host "OK: $($installer.Name)" -ForegroundColor Green
