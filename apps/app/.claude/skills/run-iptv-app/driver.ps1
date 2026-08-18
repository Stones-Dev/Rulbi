# Driver de automatización para IPTVapp (Windows desktop) — ver SKILL.md.
#
# Uso: dot-source este fichero y llama a las funciones. El estado de
# PowerShell no persiste entre invocaciones separadas de la herramienta que
# ejecuta esto, así que cada llamada debe volver a hacer `. driver.ps1`.
#
# Ejemplo (una sola invocación de PowerShell):
#   . "$PSScriptRoot\driver.ps1"
#   $hwnd = Start-IptvApp
#   Save-IptvScreenshot -Hwnd $hwnd -OutFile "C:\tmp\shot.png"
#   Send-IptvKeys -Hwnd $hwnd -Keys "^2"   # Ctrl+2
#   Stop-IptvApp

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

if (-not ("IptvWin32" -as [type])) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public struct IptvRect { public int Left; public int Top; public int Right; public int Bottom; }
public class IptvWin32 {
    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out IptvRect lpRect);
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")]
    public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();
}
"@
}

# Flags de mouse_event — clic izquierdo simple.
$script:MOUSEEVENTF_LEFTDOWN = 0x0002
$script:MOUSEEVENTF_LEFTUP = 0x0004

$script:IptvExePath = Join-Path $PSScriptRoot "..\..\..\build\windows\x64\runner\Debug\iptv_app.exe"

<#
.SYNOPSIS
Compila (si hace falta) y lanza IPTVapp, esperando a que la ventana exista.
Devuelve el HWND (IntPtr) — pásalo al resto de funciones.
#>
function Start-IptvApp {
    param(
        [switch]$Rebuild
    )
    $exe = (Resolve-Path $script:IptvExePath -ErrorAction SilentlyContinue)
    if ($Rebuild -or -not $exe) {
        $appDir = Join-Path $PSScriptRoot "..\..\.."
        Push-Location $appDir
        try {
            flutter build windows --debug | Out-Null
        } finally {
            Pop-Location
        }
        $exe = Resolve-Path $script:IptvExePath
    }
    $p = Start-Process -FilePath $exe.Path -PassThru
    $deadline = (Get-Date).AddSeconds(15)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 300
        $p.Refresh()
        if ($p.MainWindowHandle -ne [IntPtr]::Zero) { break }
    }
    if ($p.MainWindowHandle -eq [IntPtr]::Zero) {
        throw "IPTVapp no abrió ventana en 15s (PID $($p.Id))"
    }
    # Deja que el primer frame termine de pintar (fuentes/tema/datos).
    Start-Sleep -Milliseconds 1200
    [PSCustomObject]@{ Hwnd = $p.MainWindowHandle; ProcessId = $p.Id }
}

<#
.SYNOPSIS
Cierra IPTVapp por PID (más fiable que buscar por título de ventana).
#>
function Stop-IptvApp {
    param([Parameter(Mandatory)][int]$ProcessId)
    Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
}

<#
.SYNOPSIS
Trae la ventana al primer plano. Necesario antes de SendKeys — Windows
ignora las teclas de una ventana que no tiene foco.
#>
function Set-IptvForeground {
    param([Parameter(Mandatory)][IntPtr]$Hwnd)
    [IptvWin32]::ShowWindow($Hwnd, 9) | Out-Null  # SW_RESTORE
    [IptvWin32]::SetForegroundWindow($Hwnd) | Out-Null
    Start-Sleep -Milliseconds 300
}

<#
.SYNOPSIS
Envía teclas a la ventana (sintaxis de SendKeys: "^2" = Ctrl+2, "{ENTER}",
"{TAB}", "{ESC}", "  " para texto literal). Trae la ventana a primer plano
primero.
#>
function Send-IptvKeys {
    param(
        [Parameter(Mandatory)][IntPtr]$Hwnd,
        [Parameter(Mandatory)][string]$Keys,
        [int]$SettleMs = 500
    )
    Set-IptvForeground -Hwnd $Hwnd
    [System.Windows.Forms.SendKeys]::SendWait($Keys)
    Start-Sleep -Milliseconds $SettleMs
}

<#
.SYNOPSIS
Captura la ventana completa (no la pantalla entera) a un PNG. Este es el
único método fiable en este proyecto — la app no expone su árbol de
semántica a UI Automation (ver Gotchas en SKILL.md), así que no hay forma
de "hacer scroll a un elemento": lo que se ve en la ventana es lo que hay.
#>
<#
.SYNOPSIS
Clic izquierdo real en coordenadas RELATIVAS A LA VENTANA (las mismas que
verías midiendo píxeles sobre un PNG guardado por Save-IptvScreenshot,
incluida la barra de título). Necesario porque la app no expone su árbol
de semántica a UI Automation — no hay forma de "buscar el botón por
nombre" (ver Gotchas en SKILL.md); el flujo real es: capturar, mirar la
imagen, calcular el punto, clicar.
#>
function Send-IptvClick {
    param(
        [Parameter(Mandatory)][IntPtr]$Hwnd,
        [Parameter(Mandatory)][int]$X,
        [Parameter(Mandatory)][int]$Y,
        [int]$SettleMs = 500
    )
    Set-IptvForeground -Hwnd $Hwnd
    $rect = New-Object IptvRect
    [IptvWin32]::GetWindowRect($Hwnd, [ref]$rect) | Out-Null
    $screenX = $rect.Left + $X
    $screenY = $rect.Top + $Y
    [IptvWin32]::SetCursorPos($screenX, $screenY) | Out-Null
    Start-Sleep -Milliseconds 80
    [IptvWin32]::mouse_event($script:MOUSEEVENTF_LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 60
    [IptvWin32]::mouse_event($script:MOUSEEVENTF_LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds $SettleMs
}

<#
.SYNOPSIS
`$true` only if `Hwnd` genuinely holds OS foreground focus right now.
Call this BEFORE driving anything (clicks especially) — `SetForegroundWindow`
can silently fail (Windows' foreground-lock protection) while still
returning success and moving the cursor, leaving whatever the human is
actually using as the real foreground window. See Gotchas in SKILL.md —
caught live once with a human mid-game. If this returns `$false`, stop:
don't force focus over an active human session.
#>
function Confirm-IptvForeground {
    param([Parameter(Mandatory)][IntPtr]$Hwnd)
    Set-IptvForeground -Hwnd $Hwnd
    [IptvWin32]::GetForegroundWindow() -eq $Hwnd
}

function Save-IptvScreenshot {
    param(
        [Parameter(Mandatory)][IntPtr]$Hwnd,
        [Parameter(Mandatory)][string]$OutFile
    )
    Set-IptvForeground -Hwnd $Hwnd
    $rect = New-Object IptvRect
    [IptvWin32]::GetWindowRect($Hwnd, [ref]$rect) | Out-Null
    $w = $rect.Right - $rect.Left
    $h = $rect.Bottom - $rect.Top
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $g.CopyFromScreen($rect.Left, $rect.Top, 0, 0, (New-Object System.Drawing.Size $w, $h))
        $bmp.Save($OutFile, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $g.Dispose()
        $bmp.Dispose()
    }
    $OutFile
}
