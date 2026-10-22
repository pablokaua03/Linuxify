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

function Say([string]$m, [string]$c = 'Cyan') { Write-Host "==> $m" -ForegroundColor $c }
function Ask([string]$q) { if ($Yes) { return $true }; (Read-Host "$q (y/N)") -match '^[yYsS]' }
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

Say 'Linuxify installer'
New-Item -ItemType Directory -Force $Data | Out-Null

# 1. stop a running tray so files can be replaced
Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='Linuxify.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*Linuxify*' -and $_.ProcessId -ne $PID -and $_.CommandLine -notlike '*install.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

# 2. copy the kit
Say "Copying files to $Data"
foreach ($f in 'Linuxify.ps1', 'LinuxifyPanel.ps1', 'LinuxifyAlpha.ps1', 'LinuxifyDesktop.ps1', 'uninstall.ps1', 'Linuxify.exe') {
    $p = Join-Path $Src $f; if (Test-Path $p) { Copy-Item $p $Data -Force }
}
foreach ($d in 'configs') { Copy-Item (Join-Path $Src $d) $Data -Recurse -Force }
New-Item -ItemType Directory -Force (Join-Path $Data 'shell') | Out-Null
Copy-Item (Join-Path $Src 'configs\shell\init.ps1') (Join-Path $Data 'shell\init.ps1') -Force

# 3. dependencies
$deps = [ordered]@{
    'glzr-io.glazewm'        = 'GlazeWM (tiling window manager)'
    'glzr-io.zebar'          = 'Zebar (top bar)'
    'RamenSoftware.Windhawk' = 'Windhawk (taskbar mods)'
    'Fastfetch-cli.Fastfetch'= 'fastfetch (terminal banner)'
    'Starship.Starship'      = 'Starship (prompt)'
}
if (-not $NoDeps) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Say 'winget not found. Install "App Installer" from the Microsoft Store, or install the apps manually.' 'Yellow'
    } else {
        Write-Host 'Linuxify uses these apps (installed with winget):'
        $deps.GetEnumerator() | ForEach-Object { Write-Host "   - $($_.Value)  [$($_.Key)]" }
        if (Ask 'Install/update them now?') {
            foreach ($id in $deps.Keys) {
                Say "winget install $id"
                winget install --id $id -e --accept-package-agreements --accept-source-agreements --silent
            }
            if (Ask 'Install the optional JetBrainsMono Nerd Font?') {
                winget install --id DEVCOM.JetBrainsMonoNerdFont -e --accept-package-agreements --accept-source-agreements --silent
            }
        }
    }
}

# 4. configs (existing files are backed up first; uninstall restores them)
Say 'Writing configs (backups in Linuxify\backup)'
$C = Join-Path $Data 'configs'
Put (Join-Path $C 'glazewm\config.yaml')        (Join-Path $HOME '.glzr\glazewm\config.yaml')
Put (Join-Path $C 'zebar\linuxify-bar')         (Join-Path $HOME '.glzr\zebar\linuxify-bar')
Put (Join-Path $C 'zebar\settings.json')        (Join-Path $HOME '.glzr\zebar\settings.json')
Put (Join-Path $C 'starship\starship.toml')     (Join-Path $HOME '.config\starship.toml')
$ff = Join-Path $HOME '.config\fastfetch\config.jsonc'
if ((Test-Path $ff) -and -not (Test-Path (Join-Path $Data 'fastfetch.config.original.jsonc'))) { Copy-Item $ff (Join-Path $Data 'fastfetch.config.original.jsonc') }
Put (Join-Path $C 'fastfetch\config.jsonc')     $ff
Put (Join-Path $C 'fastfetch\anime-girl.txt')   (Join-Path $HOME '.config\fastfetch\anime-girl.txt')

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
        $o = Get-Content $orig -Raw | ConvertFrom-Json
        $scheme = Get-Content (Join-Path $C 'terminal\catppuccin-mocha.json') -Raw | ConvertFrom-Json
        $glob   = Get-Content (Join-Path $C 'terminal\global.json') -Raw | ConvertFrom-Json
        $defs   = Get-Content (Join-Path $C 'terminal\profile-defaults.json') -Raw | ConvertFrom-Json
        if (-not $o.PSObject.Properties['schemes']) { $o | Add-Member schemes @() }
        $o.schemes = @(@($o.schemes | Where-Object { $_.name -ne $scheme.name }) + $scheme)
        foreach ($p in $glob.PSObject.Properties) { $o | Add-Member $p.Name $p.Value -Force }
        if (-not $o.profiles.PSObject.Properties['defaults']) { $o.profiles | Add-Member defaults ([pscustomobject]@{}) }
        foreach ($p in $defs.PSObject.Properties) { $o.profiles.defaults | Add-Member $p.Name $p.Value -Force }
        [IO.File]::WriteAllText((Join-Path $Data 'wt.settings.linux.json'), ($o | ConvertTo-Json -Depth 32), $Utf8)
    } catch { Say "Windows Terminal theme skipped: $_" 'Yellow' }
} else { Say 'Windows Terminal settings not found; theme skipped.' 'Yellow' }

Say 'Windhawk: import configs\windhawk\windows-11-taskbar-styler.json in the "Windows 11 Taskbar Styler" mod settings (optional).' 'DarkGray'

# 5. startup + tray
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Data 'Linuxify.ps1') -Action TrayAutostartOn
Say 'Startup registered (HKCU Run: Linuxify)'
if (-not $NoStart) {
    $exe = Join-Path $Data 'Linuxify.exe'
    if (Test-Path $exe) { Start-Process $exe }
    else { Start-Process powershell -WindowStyle Hidden -ArgumentList "-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Data\Linuxify.ps1`"" }
    Say 'Tray started. Left-click the icon or press Ctrl+Alt+L to toggle Linux mode.' 'Green'
}
Say 'Done.' 'Green'
