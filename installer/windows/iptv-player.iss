; Instalador beta de IPTV Player (Windows) — S6 · Desktop III.
;
; Instalación POR USUARIO (PrivilegesRequired=lowest): el instalador no está
; firmado (beta privada, sin certificado de firma de código todavía — ver
; docs/packaging.md), así que pedir elevación de administrador sumaría un
; prompt de UAC encima del aviso de SmartScreen sin ganar nada a cambio.
; MSIX queda descartado para esta fase (exigiría que el usuario importe un
; certificado autofirmado a mano) pero no cerrado: MSIX y este instalador
; consumen exactamente el mismo `build\windows\x64\runner\Release`.
;
; Parámetros que inyecta build-installer.ps1 vía /D (con valores por defecto
; para poder compilar este script a mano desde el IDE de Inno Setup):
;   MyAppVersion  — versión semver (ej. "0.1.0"), sin el build number.
;   MySourceDir   — build\windows\x64\runner\Release, ya con el VC++ redist
;                   y installer\licenses\ copiados dentro por el script.
;   MyOutputDir   — carpeta donde deja el .exe final.

#define MyAppName "IPTV Player"
#define MyAppPublisher "Stones Dev"
#define MyAppExeName "iptv_app.exe"
#define MyAppURL "https://rulbi.com"

; GUID fijo y permanente para este producto (generado una vez, no cambiar):
; Inno Setup lo usa para identificar actualizaciones/desinstalaciones futuras
; del mismo producto. No tiene relación con el AppId `com.stonesdev.iptv` de
; las plataformas móviles/store — ese es un namespace distinto.
; Doble "{{" a propósito: el preprocesador sustituye {#MyAppId} como texto
; antes de que Inno interprete constantes en tiempo de compilación, así que
; el "{" inicial necesita su propio escape para no leerse como el comienzo
; de OTRA constante ("Unknown constant" si se deja en una sola llave).
#define MyAppId "{{0D924F82-8218-4D91-A952-986B49D1B0DF}"

#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif
#ifndef MySourceDir
  #define MySourceDir "..\..\apps\app\build\windows\x64\runner\Release"
#endif
#ifndef MyOutputDir
  #define MyOutputDir "..\..\dist\windows"
#endif

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
DefaultDirName={localappdata}\Programs\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
; Instalación por usuario, sin UAC — ver nota de cabecera.
PrivilegesRequired=lowest
OutputDir={#MyOutputDir}
OutputBaseFilename=IPTVPlayer-{#MyAppVersion}-beta-x64-setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
DisableWelcomePage=no
; No firmado (beta): SmartScreen avisará en el primer arranque. Aceptado a
; propósito para esta fase — ver docs/packaging.md.

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Todo el árbol de salida de `flutter build windows --release`, más el VC++
; redist y installer\licenses\ que build-installer.ps1 ya copió dentro de
; MySourceDir antes de invocar ISCC — este script no sabe (ni debe saber)
; nada sobre esas dos piezas, solo empaqueta lo que encuentra.
Source: "{#MySourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent
