<#
.SYNOPSIS
  Linuxify installer. Copies the kit to %LOCALAPPDATA%\Linuxify, optionally installs
  dependencies with winget (asks first), backs up existing configs, writes the Linuxify
  configs, registers startup and starts the tray.
.PARAMETER Yes      Do not ask questions (accept dependency install).
.PARAMETER NoDeps   Skip winget dependencies.
.PARAMETER NoStart  Do not start the tray at the end.
#>
[CmdletBinding()]
param([switch]$Yes, [switch]$NoDeps, [switch]$NoStart)
$ErrorActionPreference = 'Stop'
$Src  = $PSScriptRoot
$Data = Join-Path $env:LOCALAPPDATA 'Linuxify'
$Manifest = Join-Path $Data 'backups.txt'
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$Utf8 = New-Object System.Text.UTF8Encoding($false)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
. (Join-Path $Src 'LinuxifyLang.ps1')
. (Join-Path $Src 'LinuxifyTerminal.ps1')
function Say([string]$m, [string]$c = 'Cyan') { Write-Host "==> $m" -ForegroundColor $c }
function Ask([string]$q) { if ($Yes) { return $true }; (Read-Host "$q $(T '(y/N)')") -match '^[yYsS\u0434\u0414]' }
function Backup-Path([string]$Path) {
    if (-not (Test-Path $Path)) { return }
    $dir = Join-Path $Data ("backup\install-$Stamp")
    New-Item -ItemType Directory -Force $dir | Out-Null
    $dst = Join-Path $dir (($Path -replace '[:\\/]', '_').Trim('_'))
    Copy-Item $Path $dst -Recurse -Force
    Add-Content $Manifest "$Path|$dst"
}
function Put([string]$From, [string]$To) {
    Backup-Path $To
    $parent = Split-Path $To -Parent
    if ($parent) { New-Item -ItemType Directory -Force $parent | Out-Null }
    if (Test-Path $To) { Remove-Item $To -Recurse -Force }
    Copy-Item $From $To -Recurse -Force
}

Say (T 'Linuxify installer')
New-Item -ItemType Directory -Force $Data | Out-Null

# 1. stop a running tray so files can be replaced
Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='Linuxify.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*Linuxify*' -and $_.ProcessId -ne $PID -and $_.CommandLine -notlike '*install.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

# 2. copy the kit
Say ((T 'Copying files to {0}') -f $Data)
foreach ($f in 'Linuxify.ps1', 'LinuxifyPanel.ps1', 'LinuxifyAlpha.ps1', 'LinuxifyDesktop.ps1', 'LinuxifyLang.ps1', 'LinuxifyTerminal.ps1', 'uninstall.ps1', 'Linuxify.exe') {
    $p = Join-Path $Src $f; if (Test-Path $p) { Copy-Item $p $Data -Force }
}
foreach ($d in 'configs', 'lang', 'assets') { Copy-Item (Join-Path $Src $d) $Data -Recurse -Force }
New-Item -ItemType Directory -Force (Join-Path $Data 'shell') | Out-Null
Copy-Item (Join-Path $Src 'configs\shell\init.ps1') (Join-Path $Data 'shell\init.ps1') -Force

# 3. dependencies
$deps = [ordered]@{
    'glzr-io.glazewm'        = 'GlazeWM (' + (T 'Tiling window manager') + ')'
    'glzr-io.zebar'          = 'Zebar (' + (T 'Top bar') + ')'
    'RamenSoftware.Windhawk' = 'Windhawk (' + (T 'taskbar mods') + ')'
    'Fastfetch-cli.Fastfetch'= 'fastfetch (' + (T 'terminal banner') + ')'
    'Starship.Starship'      = 'Starship (' + (T 'prompt') + ')'
}
if (-not $NoDeps) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Say (T 'winget not found. Install "App Installer" from the Microsoft Store, or install the apps manually.') 'Yellow'
    } else {
        Write-Host (T 'Linuxify uses these apps (installed with winget):')
        $deps.GetEnumerator() | ForEach-Object { Write-Host "   - $($_.Value)  [$($_.Key)]" }
        if (Ask (T 'Install/update them now?')) {
            foreach ($id in $deps.Keys) {
                Say "winget install $id"
                winget install --id $id -e --accept-package-agreements --accept-source-agreements --silent
            }
            if (Ask (T 'Install the optional JetBrainsMono Nerd Font?')) {
                winget install --id DEVCOM.JetBrainsMonoNerdFont -e --accept-package-agreements --accept-source-agreements --silent
            }
        }
    }
}

# 4. configs (existing files are backed up first; uninstall restores them)
Say (T 'Writing configs (backups in Linuxify\backup)')
$C = Join-Path $Data 'configs'
Put (Join-Path $C 'glazewm\config.yaml')        (Join-Path $HOME '.glzr\glazewm\config.yaml')
Put (Join-Path $C 'zebar\linuxify-bar')         (Join-Path $HOME '.glzr\zebar\linuxify-bar')
Put (Join-Path $C 'zebar\settings.json')        (Join-Path $HOME '.glzr\zebar\settings.json')
Put (Join-Path $C 'starship\starship.toml')     (Join-Path $HOME '.config\starship.toml')
$ff = Join-Path $HOME '.config\fastfetch\config.jsonc'
if ((Test-Path $ff) -and -not (Test-Path (Join-Path $Data 'fastfetch.config.original.jsonc'))) { Copy-Item $ff (Join-Path $Data 'fastfetch.config.original.jsonc') }
Put (Join-Path $C 'fastfetch\config.jsonc')     $ff
Put (Join-Path $C 'fastfetch\logo-default.txt') (Join-Path $HOME '.config\fastfetch\logo-default.txt')
$logo = Join-Path $HOME '.config\fastfetch\logo.txt'
if (-not (Test-Path $logo)) { Copy-Item (Join-Path $C 'fastfetch\logo-default.txt') $logo }

# PowerShell profile hook (prompt + banner only when Linux mode is ON)
$prof = $PROFILE.CurrentUserAllHosts
if (-not ((Test-Path $prof) -and (Select-String $prof -Pattern 'Linuxify\\shell\\init' -Quiet))) {
    Backup-Path $prof
    New-Item -ItemType Directory -Force (Split-Path $prof -Parent) | Out-Null
    Add-Content $prof "`r`n# linuxify`r`n`$__li = Join-Path `$env:LOCALAPPDATA 'Linuxify\shell\init.ps1'; if (Test-Path `$__li) { . `$__li }"
}

# Windows Terminal: keep the original, build the Linux variant
$wt = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
if (Test-Path $wt) {
    try {
        $orig = Join-Path $Data 'wt.settings.original.json'
        if (-not (Test-Path $orig)) { Copy-Item $wt $orig }
        Backup-Path $wt
        # The Linux variant is rebuilt from the current settings every time Linux mode is turned on
        # (Linuxify.ps1), so this one only has to exist for the panel.
        Build-LxTerminalVariant -From $orig -To (Join-Path $Data 'wt.settings.linux.json') -OverlayDir (Join-Path $C 'terminal')
    } catch { Say ((T 'Windows Terminal theme skipped: {0}') -f $_) 'Yellow' }
} else { Say (T 'Windows Terminal settings not found; theme skipped.') 'Yellow' }

Say (T 'Windhawk: import configs\windhawk\windows-11-taskbar-styler.json in the "Windows 11 Taskbar Styler" mod settings (optional).') 'DarkGray'

# 5. startup + tray. TrayAutostartOn writes HKCU Run\Linuxify with -Boot
#    (wait for Explorer and the notification area before creating the icon).
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Data 'Linuxify.ps1') -Action TrayAutostartOn
Say (T 'Startup registered (HKCU Run: Linuxify)')
if (-not $NoStart) {
    $exe = Join-Path $Data 'Linuxify.exe'
    if (Test-Path $exe) { Start-Process $exe }
    else { Start-Process powershell -WindowStyle Hidden -ArgumentList "-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Data\Linuxify.ps1`"" }
    Say (T 'Tray started. Left-click the icon or press Ctrl+Alt+L to toggle Linux mode.') 'Green'
}
Say (T 'Done.') 'Green'
