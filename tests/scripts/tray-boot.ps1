# Regression tests for the sign-in tray launch. No Windows shell required.
$ErrorActionPreference = 'Stop'
$fail = 0
function Assert([bool]$Cond, [string]$Name) {
    if ($Cond) { Write-Output "ok  $Name" } else { Write-Output "FAIL  $Name"; $script:fail++ }
}

$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('linuxify-boot-' + [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Force $tmp | Out-Null
$prevLocal = $env:LOCALAPPDATA
try {
    $env:LOCALAPPDATA = $tmp
    # Load only the boot helpers. The tray script also references System.Drawing, which this
    # host cannot compile, and the helpers are what decide the startup command.
    $tokens = $null; $parseErrs = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'Linuxify.ps1'), [ref]$tokens, [ref]$parseErrs)
    if ($parseErrs) { throw ($parseErrs | ForEach-Object { $_.ToString() } | Out-String) }
    $want = @(
        'Test-LxExeSupportsBoot', 'Get-TrayPs1Command', 'Get-TrayLaunchCommand', 'Test-LxStartupCommandNeedsUpdate',
        'Write-LxStartup', 'Format-LxStartupError', 'Format-LxBootNotice', 'Wait-ExplorerTray', 'Test-ExplorerTrayReady'
    )
    $defs = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($name in $want) {
        $fn = $defs | Where-Object { $_.Name -eq $name } | Select-Object -First 1
        if (-not $fn) { throw "missing function $name" }
        Invoke-Expression $fn.Extent.Text
    }
    $Data = Join-Path $env:LOCALAPPDATA 'Linuxify'
    New-Item -ItemType Directory -Force $Data | Out-Null

    $exe = Join-Path $Data 'Linuxify.exe'
    $ps1cmd = Get-TrayPs1Command

    Remove-Item -LiteralPath $exe -ErrorAction SilentlyContinue
    $cmd = Get-TrayLaunchCommand
    Assert ($cmd -eq $ps1cmd) 'no exe uses the script command'
    Assert ($cmd -match '-Boot' -and $cmd -match 'Linuxify\.ps1' -and $cmd -notmatch 'Linuxify\.exe') 'script command passes -Boot to the ps1'

    [System.IO.File]::WriteAllBytes($exe, [System.Text.Encoding]::ASCII.GetBytes('older tray build without the switch'))
    $cmd = Get-TrayLaunchCommand
    Assert ($cmd -eq $ps1cmd) 'exe without [switch]$Boot is not launched'
    Assert ($cmd -notmatch 'Linuxify\.exe') 'unsupported exe is absent from the startup command'
    $broken = "`"$exe`" -Boot"
    Assert (Test-LxStartupCommandNeedsUpdate $broken) 'startup command that passes -Boot to an old exe is rewritten'
    Assert (Test-LxStartupCommandNeedsUpdate "`"$exe`"") 'startup command missing -Boot is rewritten'
    Assert (-not (Test-LxStartupCommandNeedsUpdate $ps1cmd)) 'the safe command is left as-is'
    Assert (-not (Test-LxStartupCommandNeedsUpdate '')) 'autostart off stays off'
    Assert (-not (Test-LxStartupCommandNeedsUpdate $null)) 'missing startup value stays unset'

    $utf = [System.Text.Encoding]::Unicode.GetBytes('build [switch]$Boot marker')
    [System.IO.File]::WriteAllBytes($exe, $utf)
    $cmd = Get-TrayLaunchCommand
    Assert ($cmd -eq "`"$exe`" -Boot") 'unicode marker counts as a boot-capable exe'

    [System.IO.File]::WriteAllBytes($exe, [System.Text.Encoding]::ASCII.GetBytes('prefix [switch]$Boot suffix'))
    $cmd = Get-TrayLaunchCommand
    Assert ($cmd -eq "`"$exe`" -Boot") 'ascii marker launches the exe with -Boot'
    Assert (-not (Test-LxStartupCommandNeedsUpdate $cmd)) 'matching exe command is not rewritten'

    $msg = Format-LxStartupError -Step 'wait for Explorer and the taskbar' -Reason 'taskbar probe failed: sample'
    Assert ($msg.Contains('Step: wait for Explorer and the taskbar')) 'fatal error names the step'
    Assert ($msg.Contains('taskbar probe failed: sample')) 'fatal error keeps the reason'
    Assert ($msg -notmatch 'startup failed:') 'fatal error is not the old vague startup failed line'
    Assert ($msg.Contains('Start with Windows')) 'fatal error says how to repair startup'

    $notice = Format-LxBootNotice -Step 'wait for Explorer and the taskbar' -Detail 'The taskbar probe failed: sample. Linuxify will still try to show the tray icon.'
    Assert ($notice.StartsWith('Step: wait for Explorer and the taskbar.')) 'non-fatal notice names the step'

    function Test-ExplorerTrayReady { $script:LxBootProbeError = 'sample probe failure'; return $false }
    $log = Join-Path $Data 'startup.log'
    Remove-Item -LiteralPath $log -ErrorAction SilentlyContinue
    $sw = [Diagnostics.Stopwatch]::StartNew()
    Wait-ExplorerTray
    $sw.Stop()
    Assert ($sw.Elapsed.TotalSeconds -lt 5) 'a failed taskbar probe does not wait out the full timeout'
    $logged = [System.IO.File]::ReadAllText($log)
    Assert ($logged.Contains('Step: wait for Explorer and the taskbar')) 'probe failure is logged with the step'
    Assert ($logged.Contains('sample probe failure')) 'probe failure log includes the probe error'
} finally {
    if ($null -eq $prevLocal) { Remove-Item Env:LOCALAPPDATA -ErrorAction SilentlyContinue } else { $env:LOCALAPPDATA = $prevLocal }
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

if ($fail) { Write-Output "$fail failed"; exit 1 }
Write-Output 'all passed'
exit 0
