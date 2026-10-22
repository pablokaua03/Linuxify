<#
.SYNOPSIS Undoes the kit: stops everything, removes autostart, restores backups. -RemoveApps uninstalls the packages.
#>
[CmdletBinding()]
param([switch]$DryRun, [switch]$RemoveApps, [switch]$Force)
$ErrorActionPreference = 'Continue'
$Data = Join-Path $env:LOCALAPPDATA 'Linuxify'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$__lf = Join-Path $PSScriptRoot 'LinuxifyLang.ps1'; if (-not (Test-Path $__lf)) { $__lf = Join-Path $Data 'LinuxifyLang.ps1' }; if (Test-Path $__lf) { . $__lf } else { function T([string]$k) { $k } }
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
if (Test-Path $manifest) {
    # primeiro backup de cada caminho = estado original
    foreach ($l in Get-Content $manifest) {
        $orig, $bak = $l -split '\|', 2
        if ($restored[$orig] -or -not (Test-Path $bak)) { continue }
        $restored[$orig] = $true
        Invoke-Step ((T 'restore {0}') -f $orig) { Remove-Item $orig -Recurse -Force -ErrorAction SilentlyContinue; Copy-Item $bak $orig -Recurse -Force }
    }
}
foreach ($p in @("$HOME\.glzr\glazewm\config.yaml", "$HOME\.glzr\zebar\linuxify-bar", "$HOME\.glzr\zebar\settings.json", "$HOME\.config\starship.toml", "$HOME\.config\fastfetch\logo.txt", "$HOME\.config\fastfetch\logo-default.txt")) {
    if (-not $restored[$p] -and (Test-Path $p)) { Invoke-Step ((T 'remove {0} (did not exist before)') -f $p) { Remove-Item $p -Recurse -Force } }
}
$prof = $PROFILE.CurrentUserAllHosts
if (-not $restored[$prof] -and (Test-Path $prof)) {
    Invoke-Step ((T 'remove the starship line from {0}') -f $prof) { (Get-Content $prof) | Where-Object { $_ -notmatch 'starship init powershell|^# linuxify$|Linuxify\\shell\\init' } | Set-Content $prof }
}
if ($RemoveApps) {
    foreach ($id in 'glzr-io.glazewm','glzr-io.zebar','CharlesMilette.TranslucentTB','RamenSoftware.Windhawk','Starship.Starship','Flow-Launcher.Flow-Launcher') {
        Invoke-Step "winget uninstall $id" { winget uninstall --id $id -e --silent 2>$null | Out-Null }
    }
}
# --- extras: profile global, clink, terminal padrao ---
$gp = "$env:windir\System32\WindowsPowerShell\v1.0\profile.ps1"
if ((Test-Path $gp) -and (Select-String $gp -Pattern 'Linuxify' -Quiet)) {
    Invoke-Step ((T 'remove the Linuxify line from {0} (admin)') -f $gp) {
        $tmp = Join-Path $env:TEMP 'linuxify-gp.ps1'
        "`$f='$gp'; (Get-Content `$f) | Where-Object { `$_ -notmatch 'Linuxify|^# linuxify$' } | Set-Content `$f" | Set-Content $tmp
        try { Start-Process powershell -Verb RunAs -WindowStyle Hidden -Wait -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',$tmp -ErrorAction Stop }
        catch { Write-Warning ((T 'admin declined; remove the Linuxify line from {0} manually') -f $gp) }
        Remove-Item $tmp -ErrorAction SilentlyContinue
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
Write-Host ((T 'Done. Backups remain in {0} (delete them manually if you want).') -f "$Data\backup") -ForegroundColor Green

