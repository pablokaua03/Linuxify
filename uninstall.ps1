<#
.SYNOPSIS Undoes the kit: stops everything, removes autostart, restores backups. -RemoveApps uninstalls the packages.
#>
[CmdletBinding()]
param([switch]$DryRun, [switch]$RemoveApps, [switch]$Force)
$ErrorActionPreference = 'Continue'
$Data = Join-Path $env:LOCALAPPDATA 'Linuxify'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$__lf = Join-Path $PSScriptRoot 'LinuxifyLang.ps1'; if (-not (Test-Path $__lf)) { $__lf = Join-Path $Data 'LinuxifyLang.ps1' }; if (Test-Path $__lf) { . $__lf } else { function T([string]$k) { $k } }
foreach ($__h in 'LinuxifyTerminal.ps1', 'LinuxifyBackup.ps1') {
    $__p = Join-Path $PSScriptRoot $__h; if (-not (Test-Path $__p)) { $__p = Join-Path $Data $__h }
    if (Test-Path $__p) { . $__p } else { throw "missing $__h next to uninstall.ps1" }
}
function Invoke-Step([string]$Msg, [scriptblock]$Action) {
    if ($DryRun) { Write-Host "[dry-run] $Msg" -ForegroundColor Yellow } else { Write-Host "  - $Msg"; & $Action }
}
if (-not $Force -and -not $DryRun) {
    $a = Read-Host ((T 'Undo Linuxify and restore configs?') + ' ' + (T '(y/N)'))
    if ($a -notmatch '^[sSyY\u0434\u0414]') { return }
}
$tray = Join-Path $Data 'Linuxify.ps1'
if (Test-Path $tray) {
    Invoke-Step (T 'Linux mode OFF (stop apps, remove autostart, restore Terminal)') { & powershell -NoProfile -ExecutionPolicy Bypass -File $tray -Action Off; & powershell -NoProfile -ExecutionPolicy Bypass -File $tray -Action TrayAutostartOff }
}
Invoke-Step (T 'close tray') { Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like '*Linuxify.ps1*' -or $_.CommandLine -like '*LinuxifyDesktop.ps1*' } | Where-Object ProcessId -ne $PID | ForEach-Object { Stop-Process -Id $_.ProcessId -Force } }

$manifest = Join-Path $Data 'backups.txt'
$restored = @{}
$prof = $PROFILE.CurrentUserAllHosts
$wtSettings = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
$wtHandled = (Test-Path $tray) -and (Test-Path (Join-Path $Data 'wt.settings.original.json'))   # "Linux mode OFF" above already put it back
$absent = @{}
# the first entry for each path is the state before Linuxify; later ones are copies of Linuxify's own output
foreach ($e in Get-LxManifestEntries $manifest) {
    $orig = $e.Path; $bak = $e.Backup
    if ($orig -ieq $prof) { if ($bak -eq $script:LxAbsent) { $absent[$orig] = $true }; continue }   # profile: only Linuxify's lines are removed, below
    if ($orig -ieq $wtSettings -and $wtHandled) { continue }   # Windows Terminal: restored above, with the edits made since kept
    if ($bak -eq $script:LxAbsent) { $absent[$orig] = $true; continue }
    if (-not (Test-Path $bak)) { continue }
    $restored[$orig] = $true
    Invoke-Step ((T 'restore {0}') -f $orig) { Remove-Item $orig -Recurse -Force -ErrorAction SilentlyContinue; Copy-Item $bak $orig -Recurse -Force }
}
foreach ($p in @("$HOME\.glzr\glazewm\config.yaml", "$HOME\.glzr\zebar\linuxify-bar", "$HOME\.glzr\zebar\settings.json", "$HOME\.config\starship.toml", "$HOME\.config\fastfetch\logo.txt", "$HOME\.config\fastfetch\logo-default.txt")) {
    if (-not $restored[$p] -and (Test-Path $p)) { Invoke-Step ((T 'remove {0} (did not exist before)') -f $p) { Remove-Item $p -Recurse -Force } }
}
if ((Test-Path $prof) -and (Test-LxProfileHook $prof)) {
    Invoke-Step ((T 'remove the Linuxify lines from {0}') -f $prof) {
        $empty = Remove-LxProfileHook -Path $prof
        # Linuxify created the file (it did not exist before): leave no empty file behind
        if ($empty -and $absent[$prof]) { Remove-Item $prof -Force -ErrorAction SilentlyContinue }
    }
}
if ($RemoveApps) {
    # exactly the packages install.ps1 installs (plus the optional font); nothing else
    foreach ($id in 'glzr-io.glazewm','glzr-io.zebar','RamenSoftware.Windhawk','Fastfetch-cli.Fastfetch','Starship.Starship','DEVCOM.JetBrainsMonoNerdFont') {
        Invoke-Step "winget uninstall $id" { winget uninstall --id $id -e --silent 2>$null | Out-Null }
    }
}
# --- extras: profile global, clink, terminal padrao ---
$gp = "$env:windir\System32\WindowsPowerShell\v1.0\profile.ps1"
if ((Test-Path $gp) -and (Test-LxProfileHook $gp)) {
    Invoke-Step ((T 'remove the Linuxify line from {0} (admin)') -f $gp) {
        # no script file: the cleanup is passed to the elevated PowerShell as -EncodedCommand
        try { Invoke-LxElevatedProfileCleanup -Path $gp }
        catch { Write-Warning ((T 'admin declined; remove the Linuxify line from {0} manually') -f $gp) }
    }
}
$cl = "$env:LOCALAPPDATA\clink\starship.lua"
if (Test-Path $cl) { Invoke-Step ((T 'remove {0}') -f $cl) { Remove-Item $cl -Force } }
if ($RemoveApps) {
    $cb = "${env:ProgramFiles(x86)}\clink\clink.bat"
    if (Test-Path $cb) { Invoke-Step 'clink autorun uninstall' { & $cb autorun uninstall 2>$null | Out-Null } }
}
$reg = Get-ChildItem (Join-Path $Data 'backup') -Recurse -Filter 'console-startup.reg' -ErrorAction SilentlyContinue | Sort-Object FullName | Select-Object -First 1
Invoke-Step (T 'restore default terminal (HKCU\Console\%%Startup)') {
    Remove-ItemProperty 'HKCU:\Console\%%Startup' -Name DelegationConsole,DelegationTerminal -ErrorAction SilentlyContinue
    if ($reg) { & reg.exe import $reg.FullName 2>$null | Out-Null }
}
# The originals are back. Forget the manifest and the per-install snapshots, or a later install would
# think the files it finds are still the user's originals (and skip backing them up).
Invoke-Step 'forget backups.txt and Linuxify state files' {
    foreach ($f in 'backups.txt', 'state.txt', 'wt.settings.original.json', 'wt.settings.linux.json', 'fastfetch.config.original.jsonc') {
        Remove-Item (Join-Path $Data $f) -Force -ErrorAction SilentlyContinue
    }
}
Write-Host ((T 'Done. Backups remain in {0} (delete them manually if you want).') -f "$Data\backup") -ForegroundColor Green

