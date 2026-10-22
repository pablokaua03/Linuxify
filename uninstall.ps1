<#
.SYNOPSIS Desfaz o kit: para tudo, tira autostart, restaura backups. -RemoveApps desinstala os pacotes.
#>
[CmdletBinding()]
param([switch]$DryRun, [switch]$RemoveApps, [switch]$Force)
$ErrorActionPreference = 'Continue'
$Data = Join-Path $env:LOCALAPPDATA 'Linuxify'
function Invoke-Step([string]$Msg, [scriptblock]$Action) {
    if ($DryRun) { Write-Host "[dry-run] $Msg" -ForegroundColor Yellow } else { Write-Host "  - $Msg"; & $Action }
}
if (-not $Force -and -not $DryRun) {
    $a = Read-Host 'Desfazer o Linuxify e restaurar configs? (s/N)'
    if ($a -notmatch '^[sSyY]') { return }
}
$tray = Join-Path $Data 'Linuxify.ps1'
if (Test-Path $tray) {
    Invoke-Step 'modo Linux OFF (para apps, tira autostart, restaura Terminal)' { & powershell -NoProfile -ExecutionPolicy Bypass -File $tray -Action Off; & powershell -NoProfile -ExecutionPolicy Bypass -File $tray -Action TrayAutostartOff }
}
Invoke-Step 'fechar tray' { Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like '*Linuxify.ps1*' -or $_.CommandLine -like '*LinuxifyDesktop.ps1*' } | Where-Object ProcessId -ne $PID | ForEach-Object { Stop-Process -Id $_.ProcessId -Force } }

$manifest = Join-Path $Data 'backups.txt'
$restored = @{}
if (Test-Path $manifest) {
    # primeiro backup de cada caminho = estado original
    foreach ($l in Get-Content $manifest) {
        $orig, $bak = $l -split '\|', 2
        if ($restored[$orig] -or -not (Test-Path $bak)) { continue }
        $restored[$orig] = $true
        Invoke-Step "restaurar $orig" { Remove-Item $orig -Recurse -Force -ErrorAction SilentlyContinue; Copy-Item $bak $orig -Recurse -Force }
    }
}
foreach ($p in @("$HOME\.glzr\glazewm\config.yaml", "$HOME\.glzr\zebar\linuxify-bar", "$HOME\.glzr\zebar\settings.json", "$HOME\.config\starship.toml")) {
    if (-not $restored[$p] -and (Test-Path $p)) { Invoke-Step "remover $p (nao existia antes)" { Remove-Item $p -Recurse -Force } }
}
$prof = $PROFILE.CurrentUserAllHosts
if (-not $restored[$prof] -and (Test-Path $prof)) {
    Invoke-Step "tirar linha do starship de $prof" { (Get-Content $prof) | Where-Object { $_ -notmatch 'starship init powershell|^# linuxify$|Linuxify\\shell\\init' } | Set-Content $prof }
}
if ($RemoveApps) {
    foreach ($id in 'glzr-io.glazewm','glzr-io.zebar','CharlesMilette.TranslucentTB','RamenSoftware.Windhawk','Starship.Starship','Flow-Launcher.Flow-Launcher') {
        Invoke-Step "winget uninstall $id" { winget uninstall --id $id -e --silent 2>$null | Out-Null }
    }
}
# --- extras: profile global, clink, terminal padrao ---
$gp = "$env:windir\System32\WindowsPowerShell\v1.0\profile.ps1"
if ((Test-Path $gp) -and (Select-String $gp -Pattern 'Linuxify' -Quiet)) {
    Invoke-Step "tirar linha do Linuxify de $gp (admin)" {
        $tmp = Join-Path $env:TEMP 'linuxify-gp.ps1'
        "`$f='$gp'; (Get-Content `$f) | Where-Object { `$_ -notmatch 'Linuxify|^# linuxify$' } | Set-Content `$f" | Set-Content $tmp
        try { Start-Process powershell -Verb RunAs -WindowStyle Hidden -Wait -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',$tmp -ErrorAction Stop }
        catch { Write-Warning "admin recusado; remova manualmente a linha do Linuxify em $gp" }
        Remove-Item $tmp -ErrorAction SilentlyContinue
    }
}
$cl = "$env:LOCALAPPDATA\clink\starship.lua"
if (Test-Path $cl) { Invoke-Step "remover $cl" { Remove-Item $cl -Force } }
if ($RemoveApps) {
    $cb = "${env:ProgramFiles(x86)}\clink\clink.bat"
    if (Test-Path $cb) { Invoke-Step 'clink autorun uninstall' { & $cb autorun uninstall 2>$null | Out-Null } }
}
$reg = Get-ChildItem (Join-Path $Data 'backup') -Recurse -Filter 'console-startup.reg' -ErrorAction SilentlyContinue | Sort-Object FullName | Select-Object -First 1
Invoke-Step 'restaurar terminal padrao (HKCU\Console\%%Startup)' {
    Remove-ItemProperty 'HKCU:\Console\%%Startup' -Name DelegationConsole,DelegationTerminal -ErrorAction SilentlyContinue
    if ($reg) { & reg.exe import $reg.FullName 2>$null | Out-Null }
}
Write-Host "Pronto. Backups continuam em $Data\backup (apague manualmente se quiser)." -ForegroundColor Green

