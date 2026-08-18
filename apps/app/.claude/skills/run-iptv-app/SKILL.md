---
name: run-iptv-app
description: Build, run, and drive the IPTVapp Windows desktop app (Flutter, apps/app). Use when asked to run iptv_app, launch the desktop app, take a screenshot of a screen, verify a visual/design change against Figma, or click through the app to reach a specific screen (player overlay, VOD/series detail, etc).
---

Windows desktop Flutter app (`apps/app`, package `iptv_player`). Drive it via
`.claude/skills/run-iptv-app/driver.ps1` — a PowerShell module of functions
(`Start-IptvApp`, `Send-IptvClick`, `Send-IptvKeys`, `Save-IptvScreenshot`)
that launches the real `.exe`, clicks/types into it with real OS input
events, and captures real window screenshots. There is **no GUI
automation via UI Automation / accessibility tree** — see Gotchas — so
every interaction is a real mouse click at pixel coordinates you read off
a screenshot, not a "find element by name" call.

All paths below are relative to `apps/app/`.

## Prerequisites

Windows 10/11 with the Flutter SDK on `PATH` (`flutter --version` must
work) and the Windows desktop toolchain already enabled
(`flutter config --enable-windows-desktop`, already on in this repo).
No extra OS packages — this driver only uses PowerShell 5.1 built-ins
(`System.Drawing`, `System.Windows.Forms`, raw `user32.dll` P/Invoke).

For real content (posters, backdrops, live "now airing" data) instead of
fallback icons, the synthetic Xtream test server should be running —
see `tool/xtream-test-server/README.md`:

```bash
cd tool/xtream-test-server
docker compose -f docker-compose.dev.yml up --build -d
curl -s "http://127.0.0.1:8081/player_api.php?username=test&password=test" | head -c 200
```

The app persists its own SQLite DB in the user's `Documents` folder, so a
source added once (host `127.0.0.1:8081`, user/pass `test`/`test`, via
**Fuentes → Nueva fuente** in the running app) survives across relaunches
— you don't need to re-add it every session.

## Build

```powershell
cd apps/app
flutter build windows --debug
```

Produces `apps/app/build/windows/x64/runner/Debug/iptv_app.exe`. Takes
~45s from a warm cache, longer cold. `Start-IptvApp` in the driver does
this for you when the exe doesn't exist yet, or when called with
`-Rebuild`.

## Run (agent path)

Dot-source the driver, then call its functions. **PowerShell tool calls
in this harness don't share state across invocations** — re-run the
`. driver.ps1` line (and re-declare `$hwnd` from the value `Start-IptvApp`
returned) every time you call this from a fresh tool call:

```powershell
. "apps\app\.claude\skills\run-iptv-app\driver.ps1"
$app = Start-IptvApp          # builds if needed, launches, waits for the window
$app.Hwnd                     # save this — every other call needs it
$app.ProcessId                # save this too — for Stop-IptvApp at the end

if (-not (Confirm-IptvForeground -Hwnd $app.Hwnd)) {
    # Something else (the human's actual work) has real foreground focus.
    # Stop here — see Gotchas. Do not proceed to Send-IptvClick.
}

Save-IptvScreenshot -Hwnd $app.Hwnd -OutFile "C:\tmp\shot.png"
```

Then read `C:\tmp\shot.png` with your Read tool, look at it, measure the
pixel coordinates (window-relative — same origin as the screenshot,
titlebar included) of whatever you want to click, and:

```powershell
. "apps\app\.claude\skills\run-iptv-app\driver.ps1"
$hwnd = [IntPtr]<the number Start-IptvApp printed>
Send-IptvClick -Hwnd $hwnd -X 398 -Y 566 -SettleMs 1500
Save-IptvScreenshot -Hwnd $hwnd -OutFile "C:\tmp\shot2.png"
```

Repeat: screenshot → look → click/type → screenshot. This is the whole
loop; there is no shortcut around actually looking at each frame.

| function | what it does |
|---|---|
| `Start-IptvApp [-Rebuild]` | Builds (if needed) and launches the app, waits up to 15s for its window, returns `{Hwnd, ProcessId}` |
| `Stop-IptvApp -ProcessId <id>` | Kills the app |
| `Confirm-IptvForeground -Hwnd <h>` | `$true` only if `Hwnd` genuinely has OS foreground focus right now — call before driving anything, see Gotchas |
| `Save-IptvScreenshot -Hwnd <h> -OutFile <path>` | Brings the window to front, captures **the window's own bounds** (title bar included) to a PNG |
| `Send-IptvClick -Hwnd <h> -X <n> -Y <n> [-SettleMs 500]` | Real left-click at window-relative pixel coordinates (`SendInput`, not the legacy `mouse_event`) |
| `Send-IptvKeys -Hwnd <h> -Keys <s> [-SettleMs 500]` | Real keystrokes via `SendKeys` syntax (`"^2"` = Ctrl+2, `"{ENTER}"`, `"{ESC}"`) |
| `Set-IptvForeground -Hwnd <h>` | Brings the window to front (the other functions call this themselves — rarely needed directly) |

Screenshots in this doc's own verification runs went to a scratch temp
dir — put yours wherever your session's scratchpad is; there's no fixed
convention.

## Run (human path)

`flutter run -d windows` from `apps/app/` for hot reload during active
development. Useless for an agent (blocks the terminal, no scriptable
handle) — use the driver instead.

## Test

```bash
melos run test        # from repo root — all 6 packages
flutter test          # from apps/app/ — just this package
```

---

## Gotchas

- **Check whose window is actually in the foreground before trusting a
  screenshot — this driver shares the one physical screen with whatever
  the human is doing.** `SetForegroundWindow` can silently fail (Windows'
  foreground-lock protection: a background process generally can't steal
  focus from whatever app the user is actively using) while still
  returning `$true` and moving the literal OS cursor — `Save-IptvScreenshot`
  will then happily save a screenshot of the human's actual foreground
  app (their browser, their game, whatever) at the coordinates of our
  window, not our window. Caught live: the human was playing a game:
  ```powershell
  [IptvFg2]::GetForegroundWindow()   # returned the game's HWND, not ours
  ```
  Before driving anything — and especially before any `Send-IptvClick`,
  which could misclick into whatever's actually focused — call
  `Confirm-IptvForeground -Hwnd $hwnd`. If it returns `$false`, **stop**:
  don't force focus over a human's active session. Wait, or ask.

- **No UI Automation tree — don't try `AutomationElement.FindFirst` by
  name.** `[System.Windows.Automation.AutomationElement]::FromHandle($hwnd)`
  followed by `FindAll(..., TrueCondition)` returns exactly **one**
  element (`Name='FLUTTERVIEW'`, `ControlType.Pane`) no matter how long
  you poll or wait — Flutter's Windows embedder never populates its
  semantics/accessibility bridge for a plain UIA client the way it does
  for an actual screen reader. There is no "find the button labeled X"
  path here. Screenshot, measure pixels, click coordinates — that's the
  only reliable method for this app.

- **`SendKeys("{ENTER}")` does not activate a focused card.** A card
  can show the `IptvFocus` white ring/halo (real Flutter focus) without
  Enter/Space triggering its `onTap` — this app's `InkWell`-based cards
  don't wire an `ActivateIntent` binding for keyboard activation. Use a
  real mouse click instead of trying to drive focus + Enter.

- **`mouse_event()` (the legacy Win32 call) silently does nothing to
  this app; `SendInput` works.** Both report success, both move the
  literal OS cursor (verified with `GetCursorPos`), both bring the
  window to the confirmed foreground (verified with
  `GetForegroundWindow`) — but only `SendInput`-based clicks register
  as taps inside the Flutter engine. `Send-IptvClick` already uses
  `SendInput`; if you hand-roll input instead of using the driver,
  don't reach for `mouse_event`.

- **The "Ahora en tus canales" row on Home has no `onTap` wired — this
  is a real app gap, not a driver bug.** Clicking any of those three
  live-channel cards does nothing (confirmed: correct coordinates,
  successful click per the above, zero visual change). Every other
  card on Home (Continuar viendo, Favoritos) and the full channel list
  under **TV en directo** in the rail navigate correctly — use those
  instead when you need to reach the live player.

- **`Ctrl+<digit>` rail shortcuts (`Send-IptvKeys -Keys "^2"`) are
  unreliable right after a `Navigator.pop()`** (e.g. right after
  clicking a screen's back button) — the shell's `CallbackShortcuts`
  binding needs its own `Focus` node focused, which a just-disposed
  child screen doesn't hand back reliably. Click the rail item directly
  instead of relying on the shortcut in that situation.

- **NavigationRail destinations need the click closer to the icon/label
  center than you'd guess** — a click a few pixels off (still visually
  "on" the row) can land in dead space between rows and do nothing.
  Aim at the icon glyph itself, not just "somewhere in the 48px row."

## Troubleshooting

- **`Start-IptvApp` throws "no abrió ventana en 15s"**: the previous
  run's process is probably still alive and the new one is failing to
  bind/start. `Get-Process iptv_app | Stop-Process -Force`, then retry.

- **Screenshot looks like the OS desktop or another window, not the
  app**: `Save-IptvScreenshot` calls `Set-IptvForeground` first, but if
  another window (e.g. a permission dialog) grabbed focus in between
  your last action and the screenshot, that dialog wins. Screenshot
  again after an extra `Start-Sleep -Milliseconds 500`.

- **PowerShell errors with "No se encuentra el tipo [...]" for a type
  you defined in an earlier tool call**: expected — each PowerShell
  tool invocation is a fresh process with no memory of previous
  `Add-Type` calls or variables. Always start the call with
  `. driver.ps1` (and re-declare `$hwnd`) rather than assuming anything
  from a prior call is still around.
