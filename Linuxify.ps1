<#
.SYNOPSIS Tray "Linuxify": liga/desliga o modo Linux. Ctrl+Alt+L alterna.
  Sem parametro = abre o tray. -Boot = espera o Explorer e a area de notificacao (entrada do Run no logon).
  -Action On|Off|Toggle|TrayAutostartOn|TrayAutostartOff = executa e sai.
#>
[CmdletBinding()]
param(
    [ValidateSet('', 'On', 'Off', 'Toggle', 'TrayAutostartOn', 'TrayAutostartOff')][string]$Action = '',
    [switch]$Boot
)
$Data  = Join-Path $env:LOCALAPPDATA 'Linuxify'
$State = Join-Path $Data 'state.txt'
$Run   = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$WtSet = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
# Shared helpers (UTF-8 file access, Windows Terminal merge). Installed next to this script.
$__lt = Join-Path $Data 'LinuxifyTerminal.ps1'; if (-not (Test-Path $__lt) -and $PSScriptRoot) { $__lt = Join-Path $PSScriptRoot 'LinuxifyTerminal.ps1' }
if (Test-Path $__lt) { . $__lt }
$Apps  = @(
    @{ Key = 'Linuxify.GlazeWM';      Proc = 'glazewm';      Exe = "$env:ProgramFiles\glzr.io\GlazeWM\glazewm.exe" }
)
# Zebar e iniciado pelo Linuxify depois do GlazeWM (sem duplicar).

function Get-LinuxState { if (Test-Path $State) { (Get-Content $State -Raw).Trim() -eq 'on' } else { $false } }
function Find-Exe([hashtable]$App) {
    if ($App.Exe -like 'shell:*' -or (Test-Path $App.Exe)) { return $App.Exe }
    $c = Get-Command "$($App.Proc).exe" -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    $alt = Get-ChildItem "$env:LOCALAPPDATA\Programs", $env:ProgramFiles -Recurse -Filter "$($App.Proc).exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($alt) { $alt.FullName } else { $null }
}
function Set-Windhawk([bool]$Enabled) {
    $svc = Get-Service -Name 'Windhawk' -ErrorAction SilentlyContinue
    if ($Enabled) {
        if ($svc -and $svc.Status -ne 'Running') { Start-Process sc.exe -ArgumentList 'start Windhawk' -Verb RunAs -WindowStyle Hidden -ErrorAction SilentlyContinue }
    } else {
        Get-Process windhawk -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq 'Running') { Start-Process sc.exe -ArgumentList 'stop Windhawk' -Verb RunAs -WindowStyle Hidden -ErrorAction SilentlyContinue }
    }
}
function Restart-Explorer { Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force; Start-Sleep 2; if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe } }

function Start-Zebar {
    $z = "$env:ProgramFiles\glzr.io\Zebar\zebar.exe"
    if (-not (Test-Path $z)) { $c = Get-Command zebar.exe -ErrorAction SilentlyContinue; if ($c) { $z = $c.Source } else { return } }
    Set-ItemProperty $Run 'Linuxify.Zebar' "`"$z`""
    for ($i = 0; $i -lt 10 -and -not (Get-Process zebar -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Milliseconds 500 }
    if (-not (Get-Process zebar -ErrorAction SilentlyContinue)) { Start-Process $z }
}

function Set-LxTerminalLinux {
    # OFF -> ON: today's Windows Terminal settings become the "original" and the Linux look is added on
    # top of them, so changes made since the last time are kept. Nothing is touched if the settings
    # cannot be parsed (for example when they contain comments).
    $lx = Join-Path $Data 'wt.settings.linux.json'
    if (-not (Test-Path $WtSet)) { return }
    if ((Test-Path $lx) -and ((Get-FileHash $WtSet).Hash -eq (Get-FileHash $lx).Hash)) { return }  # already the Linux variant
    try {
        Build-LxTerminalVariant -From $WtSet -To $lx -OverlayDir (Join-Path $Data 'configs\terminal')
        Copy-Item $WtSet (Join-Path $Data 'wt.settings.original.json') -Force
        Copy-Item $lx $WtSet -Force
    } catch { Write-LxStartup "Windows Terminal theme not applied: $_" }
}
function Enable-Linux {
    foreach ($a in $Apps) {
        $exe = Find-Exe $a
        if (-not $exe) { continue }
        if ($exe -like 'shell:*') { Set-ItemProperty $Run $a.Key "explorer.exe $exe" } else { Set-ItemProperty $Run $a.Key "`"$exe`"" }
        if (-not (Get-Process $a.Proc -ErrorAction SilentlyContinue)) { if ($exe -like 'shell:*') { Start-Process explorer.exe -ArgumentList $exe } else { Start-Process $exe } }
    }
    Start-Zebar
    Set-Windhawk $true
    if (-not (Get-LinuxState)) { Set-LxTerminalLinux }
    Set-Content $State 'on'
}
function Disable-Linux {
    foreach ($a in $Apps) { Remove-ItemProperty $Run $a.Key -ErrorAction SilentlyContinue }
    Remove-ItemProperty $Run 'Linuxify.Zebar' -ErrorAction SilentlyContinue
    $gz = Find-Exe $Apps[0]   # same lookup as Enable-Linux (Program Files), not only PATH
    if ($gz) { & $gz command wm-exit 2>$null }
    foreach ($p in 'glazewm', 'glazewm-watcher', 'zebar') { Get-Process $p -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue }
    # Windhawk fica sempre ligado
    $orig = Join-Path $Data 'wt.settings.original.json'
    if ((Test-Path $orig) -and (Test-Path $WtSet)) {
        if (-not (Test-Path (Join-Path $Data 'wt.settings.linux.json'))) { Copy-Item $WtSet (Join-Path $Data 'wt.settings.linux.json') }
        Backup-LxTerminalEdits -WtSettings $WtSet -LinuxVariant (Join-Path $Data 'wt.settings.linux.json') -BackupDir (Join-Path $Data 'backup') | Out-Null
        Copy-Item $orig $WtSet -Force
    }
    # (Windhawk sempre ligado, sem restart do explorer)
    Set-Content $State 'off'
}
function Test-LxExeSupportsBoot([string]$Path) {
    # ps2exe stores the script as text inside Linuxify.exe. A build from before [switch]$Boot
    # stops at once with: A parameter cannot be found that matches parameter name 'Boot'.
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $false }
    $fs = $null
    try {
        $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $len = [int64]$fs.Length
        if ($len -le 0 -or $len -gt 20MB) { return $false }
        $buf = [byte[]]::new([int]$len)
        $off = 0
        while ($off -lt $buf.Length) {
            $n = $fs.Read($buf, $off, $buf.Length - $off)
            if ($n -le 0) { break }
            $off += $n
        }
        $needle = '[switch]$Boot'
        if ([System.Text.Encoding]::ASCII.GetString($buf).Contains($needle)) { return $true }
        return [System.Text.Encoding]::Unicode.GetString($buf).Contains($needle)
    } catch { return $false } finally { if ($fs) { $fs.Dispose() } }
}
function Get-TrayPs1Command {
    "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -STA -File `"$Data\Linuxify.ps1`" -Boot"
}
function Get-TrayLaunchCommand {
    $exe = Join-Path $Data 'Linuxify.exe'
    # -Boot waits for Explorer and Shell_TrayWnd. Only an exe that declares the switch can take it.
    if ((Test-Path -LiteralPath $exe) -and (Test-LxExeSupportsBoot $exe)) { return "`"$exe`" -Boot" }
    return (Get-TrayPs1Command)
}
function Test-LxStartupCommandNeedsUpdate([string]$Current) {
    # Empty means Start with Windows is off; do not turn it back on.
    if (-not $Current) { return $false }
    return ([string]$Current -ne [string](Get-TrayLaunchCommand))
}
function Set-TrayAutostart([bool]$On) {
    if ($On) { Set-ItemProperty $Run 'Linuxify' (Get-TrayLaunchCommand) }
    else { Remove-ItemProperty $Run 'Linuxify' -ErrorAction SilentlyContinue }
}
function Update-TrayBootArg {
    # Rewrite a startup command that is missing -Boot, or that passes -Boot to an exe which rejects it.
    $cur = (Get-ItemProperty $Run -Name 'Linuxify' -ErrorAction SilentlyContinue).Linuxify
    if (-not (Test-LxStartupCommandNeedsUpdate $cur)) { return }
    Set-TrayAutostart $true
}
function Write-LxStartup([string]$Message) {
    try { Add-Content (Join-Path $Data 'startup.log') ("{0} {1}" -f (Get-Date).ToString('s'), $Message) -ErrorAction Stop } catch {}
}
function Format-LxStartupError([string]$Step, [string]$Reason) {
    $log = Join-Path $Data 'startup.log'
    $why = if ($Reason) { $Reason.Trim() } else { 'No details were returned.' }
    if ($why -notmatch '[.!?]$') { $why += '.' }
    "Linuxify could not finish starting. Step: $Step. $why What to do: sign in to Windows, then start Linuxify again. If this happens every time you sign in, turn Start with Windows off and on once so the startup command is rewritten. Log: $log"
}
function Format-LxBootNotice([string]$Step, [string]$Detail) {
    "Step: $Step. $Detail"
}
function Show-LxStartupError([string]$Step, [string]$Reason) {
    $msg = Format-LxStartupError -Step $Step -Reason $Reason
    Write-LxStartup $msg
    try {
        if (-not ('System.Windows.Forms.MessageBox' -as [type])) { Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop }
        [void][System.Windows.Forms.MessageBox]::Show($msg, 'Linuxify', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    } catch {}
    $msg
}
function Add-LxBootType {
    if ('LxBoot' -as [type]) { return }
    # user32.dll exports FindWindowW, not FindWindow. Bind that entry point so the taskbar
    # probe does not depend on charset suffix decoration.
    Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class LxBoot {
    [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "FindWindowW", SetLastError = true)]
    public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
}
'@
}
function Test-ExplorerTrayReady {
    if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) { return $false }
    try {
        Add-LxBootType
        $hwnd = [LxBoot]::FindWindow('Shell_TrayWnd', [NullString]::Value)
        return ($hwnd -ne [IntPtr]::Zero)
    } catch {
        $script:LxBootProbeError = $_.Exception.Message
        return $false
    }
}
function Wait-ExplorerTray {
    # Poll until explorer.exe is up and the taskbar window exists, then a short extra delay
    # so the notification area can finish creating. Give up after ~60s, or immediately if the
    # probe itself fails, and try to show the icon anyway.
    $script:LxBootProbeError = $null
    $ready = $false
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt 60) {
        if (Test-ExplorerTrayReady) { $ready = $true; break }
        if ($script:LxBootProbeError) { break }
        Start-Sleep -Milliseconds 500
    }
    if (-not $ready) {
        $why = if ($script:LxBootProbeError) { "The taskbar probe failed: $($script:LxBootProbeError)" } else { 'explorer.exe and the Shell_TrayWnd window were not both ready within 60 seconds.' }
        Write-LxStartup (Format-LxBootNotice -Step 'wait for Explorer and the taskbar' -Detail "$why Linuxify will still try to show the tray icon.")
    } else { Start-Sleep -Seconds 2 }
}

New-Item -ItemType Directory -Force $Data | Out-Null
switch ($Action) {
    'On' { Enable-Linux; return }
    'Off' { Disable-Linux; return }
    'Toggle' { if (Get-LinuxState) { Disable-Linux } else { Enable-Linux }; return }
    'TrayAutostartOn' { Set-TrayAutostart $true; return }
    'TrayAutostartOff' { Set-TrayAutostart $false; return }
}

# ---- Tray ----
$mutex = New-Object System.Threading.Mutex($false, 'Local\LinuxifyTray')
if (-not $mutex.WaitOne(0)) { $mutex.Dispose(); return }
$tray = $null
$hk = $null
$script:LxStartStep = 'start the tray'
try {
    $script:LxStartStep = 'refresh the startup command'
    try { Update-TrayBootArg } catch { Write-LxStartup (Format-LxStartupError -Step $script:LxStartStep -Reason $_.Exception.Message) }
    # -Boot is what the Run entry passes. Also wait when the shell is not up yet, so an
    # older startup command (no -Boot) still survives the logon that migrates it.
    $script:LxStartStep = 'wait for Explorer and the taskbar'
    if ($Boot -or -not (Test-ExplorerTrayReady)) { Wait-ExplorerTray }
    $script:LxStartStep = 'load Windows Forms'
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing -ErrorAction Stop
    $script:LxStartStep = 'register the hotkey window'
    Add-Type -ErrorAction Stop -ReferencedAssemblies System.Windows.Forms -TypeDefinition @'
using System; using System.Runtime.InteropServices; using System.Windows.Forms;
public class HotkeyWindow : NativeWindow, IDisposable {
  [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr h, int id, uint mod, uint vk);
  [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr h, int id);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern uint RegisterWindowMessage(string lpString);
  public event EventHandler Pressed;
  public event EventHandler TaskbarCreated;
  public bool Ok;
  uint taskbarMsg;
  public HotkeyWindow(uint mod, uint vk) {
    CreateHandle(new CreateParams());
    Ok = RegisterHotKey(Handle, 1, mod, vk);
    taskbarMsg = RegisterWindowMessage("TaskbarCreated");
  }
  protected override void WndProc(ref Message m) {
    if (m.Msg == 0x0312 && Pressed != null) Pressed(this, EventArgs.Empty);
    if (taskbarMsg != 0 && m.Msg == (int)taskbarMsg && TaskbarCreated != null) TaskbarCreated(this, EventArgs.Empty);
    base.WndProc(ref m);
  }
  public void Dispose() { UnregisterHotKey(Handle, 1); DestroyHandle(); }
}
'@

$script:LxStartStep = 'load helpers and language'
. (Join-Path $Data 'LinuxifyAlpha.ps1')
$__lf = Join-Path $Data 'LinuxifyLang.ps1'; if (-not (Test-Path $__lf)) { if ($PSScriptRoot) { $__lf = Join-Path $PSScriptRoot 'LinuxifyLang.ps1' } }; if (Test-Path $__lf) { . $__lf } else { function T([string]$k) { $k } }
function New-StateIcon([bool]$On) {
    $bmp = New-Object System.Drawing.Bitmap 16, 16
    $g = [System.Drawing.Graphics]::FromImage($bmp); $g.SmoothingMode = 'AntiAlias'
    $col = if ($On) { [System.Drawing.Color]::FromArgb(203, 166, 247) } else { [System.Drawing.Color]::FromArgb(108, 112, 134) }
    $g.Dispose(); $bmp.Dispose()
    $sz = [System.Windows.Forms.SystemInformation]::SmallIconSize.Width; if ($sz -lt 16) { $sz = 16 }
    # penguin logo: multi-size assets\linuxify.ico (16/20/24/32/48...), picked at the tray's real size
    $ico = @((Join-Path $Data 'assets\linuxify.ico'), (Join-Path $(if ($PSScriptRoot) { $PSScriptRoot } else { $Data }) 'assets\linuxify.ico')) | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($ico) {
        $ic = New-Object System.Drawing.Icon($ico, $sz, $sz)
        if ($On) { return $ic }
        $src = $ic.ToBitmap(); $ic.Dispose(); $bmp = New-Object System.Drawing.Bitmap $sz, $sz; $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.InterpolationMode = 'HighQualityBicubic'; $ia = New-Object System.Drawing.Imaging.ImageAttributes
        $m = New-Object System.Drawing.Imaging.ColorMatrix(,[single[][]]@(@(0.3,0.3,0.3,0,0), @(0.59,0.59,0.59,0,0), @(0.11,0.11,0.11,0,0), @(0,0,0,0.85,0), @(0,0,0,0,1))); $ia.SetColorMatrix($m)
        $g.DrawImage($src, (New-Object System.Drawing.Rectangle 0, 0, $sz, $sz), 0, 0, $src.Width, $src.Height, 'Pixel', $ia); $g.Dispose(); $src.Dispose()
        return [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
    }
    $bmp = [LxAlpha]::Logo(16, $col); [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
}

# NotifyIcon (and Visible) fails while the notification area is still coming up. Try a few times.
$script:LxStartStep = 'create the tray icon'
for ($notifyTry = 1; $notifyTry -le 3; $notifyTry++) {
    try {
        $tray = New-Object System.Windows.Forms.NotifyIcon
        $tray.Text = 'Linuxify'
        $tray.Visible = $true
        if ($notifyTry -gt 1) { Write-LxStartup ("NotifyIcon ready on attempt {0}/3" -f $notifyTry) }
        break
    } catch {
        Write-LxStartup ("NotifyIcon attempt {0}/3 failed: {1}" -f $notifyTry, $_.Exception.Message)
        if ($tray) { try { $tray.Visible = $false; $tray.Dispose() } catch {} ; $tray = $null }
        if ($notifyTry -ge 3) { throw }
        Start-Sleep -Seconds 2
    }
}
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$miPanel = $menu.Items.Add('')
$miPanel.Font = New-Object System.Drawing.Font($miPanel.Font, [System.Drawing.FontStyle]::Bold)
$miToggle = $menu.Items.Add('')
$miBoot = New-Object System.Windows.Forms.ToolStripMenuItem ''
$menu.Items.Add($miBoot) | Out-Null
$menu.Items.Add('-') | Out-Null
$miUninst = $menu.Items.Add('')
$miExit = $menu.Items.Add('')

function Update-Ui {
    $on = Get-LinuxState
    if ((Get-Command Get-LxLang -ErrorAction SilentlyContinue) -and (Get-LxLang) -ne $global:LxLang) { Import-LxLang }
    $miPanel.Text = T 'Open panel...'; $miBoot.Text = T 'Start with Windows'; $miUninst.Text = T 'Uninstall everything...'; $miExit.Text = T 'Quit Linuxify'
    $tray.Icon = New-StateIcon $on
    $tray.Text = "Linuxify: $(if ($on) {'ON'} else {'OFF'}) (Ctrl+Alt+L)"
    $miToggle.Text = if ($on) { T 'Linux mode: ON  (click to turn off)' } else { T 'Linux mode: OFF (click to turn on)' }
    $miBoot.Checked = [bool](Get-ItemProperty $Run -Name 'Linuxify' -ErrorAction SilentlyContinue)
}
function Switch-Mode {
    if (Get-LinuxState) { Disable-Linux } else { Enable-Linux }
    Update-Ui
    $tray.ShowBalloonTip(1500, 'Linuxify', "$(T 'Linux mode') $(if (Get-LinuxState) {'ON'} else {'OFF'})", 'None')
}
$miToggle.add_Click({ Switch-Mode })
function Open-Panel { Start-Process powershell -WindowStyle Hidden -ArgumentList "-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Data\LinuxifyPanel.ps1`"" }
$miPanel.add_Click({ Open-Panel })
$miBoot.add_Click({ Set-TrayAutostart (-not $miBoot.Checked); Update-Ui })
$miUninst.add_Click({
    $r = [System.Windows.Forms.MessageBox]::Show((T 'Undo everything and restore the original configs?'), 'Linuxify', 'YesNo', 'Warning')
    if ($r -eq 'Yes') {
        $tray.Visible = $false
        Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$Data\uninstall.ps1`" -Force"
        [System.Windows.Forms.Application]::Exit()
    }
})
$miExit.add_Click({ $tray.Visible = $false; [System.Windows.Forms.Application]::Exit() })
$tray.ContextMenuStrip = $menu
$menu.add_Opening({ Update-Ui })
$tray.add_MouseClick({ if ($_.Button -eq 'Left') { Switch-Mode } })

$hk = New-Object HotkeyWindow ([uint32](0x0001 -bor 0x0002 -bor 0x4000), [uint32]0x4C)  # Alt|Ctrl|NoRepeat + L
$hk.add_Pressed({ Switch-Mode })
# Explorer broadcasts TaskbarCreated when it restarts; the old icon is gone until we show it again.
$hk.add_TaskbarCreated({
    try { $tray.Visible = $false; $tray.Visible = $true }
    catch { Write-LxStartup ("taskbar created, icon refresh failed: {0}" -f $_.Exception.Message) }
})
Update-Ui
$tray.Visible = $true
if (-not $hk.Ok) { $tray.ShowBalloonTip(3000, 'Linuxify', (T 'Ctrl+Alt+L is already in use; use the icon.'), 'Warning') }
# Transparencia: reaplica regras salvas (inicio + janelas novas) se 'Aplicar ao iniciar'
$tmT = New-Object System.Windows.Forms.Timer; $tmT.Interval = 1500
$tmT.add_Tick({ try { $c = Get-LxTransp; if ($c.ApplyOnStart -ne $false) { Invoke-LxTranspRules $c }; Invoke-LxTranspManual } catch {} }); $tmT.Start()
# Watchdog do Zebar: o Zebar 3.3.1 crasha (ucrtbase 0xc0000005, provider de audio ao trocar fone Bluetooth).
# Se ele estiver no autostart do Linuxify e o GlazeWM estiver rodando, religa em ~3 s. Nunca desiste:
# depois de 5 religadas em 10 min, espera cada vez mais entre tentativas (15 s, 30 s, 60 s... ate 5 min).
$script:zbHist = New-Object System.Collections.ArrayList
$script:zbNext = [datetime]::MinValue
$tmZ = New-Object System.Windows.Forms.Timer; $tmZ.Interval = 3000
$tmZ.add_Tick({ try {
    if (-not (Get-ItemProperty $Run -Name 'Linuxify.Zebar' -ErrorAction SilentlyContinue)) { return }
    if (-not (Get-Process glazewm -ErrorAction SilentlyContinue)) { return }
    if (Get-Process zebar -ErrorAction SilentlyContinue) { return }
    $now = Get-Date; if ($now -lt $script:zbNext) { return }
    @($script:zbHist | Where-Object { ($now - $_).TotalMinutes -gt 10 }) | ForEach-Object { [void]$script:zbHist.Remove($_) }
    $z = "$env:ProgramFiles\glzr.io\Zebar\zebar.exe"
    if (-not (Test-Path $z)) { $c = Get-Command zebar.exe -ErrorAction SilentlyContinue; if ($c) { $z = $c.Source } else { return } }
    Start-Process $z; [void]$script:zbHist.Add($now)
    $extra = $script:zbHist.Count - 5
    if ($extra -gt 0) { $script:zbNext = $now.AddSeconds([math]::Min(300, 15 * [math]::Pow(2, $extra - 1))) }
    Add-Content (Join-Path $Data 'watchdog.log') "$($now.ToString('s')) zebar restarted" -ErrorAction SilentlyContinue
} catch {} }); $tmZ.Start()
# Reaplica estado salvo no boot (autostart dos apps ja cuida; isto garante coerencia)
function Start-LxDesktop { $dc = Join-Path $Data 'desktop.json'; if ((Test-Path $dc) -and ((Get-Content $dc -Raw | ConvertFrom-Json).Enabled)) { Start-Process powershell -WindowStyle Hidden -ArgumentList "-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Data\LinuxifyDesktop.ps1`"" } }
try { Start-LxDesktop } catch {}
$script:LxStartStep = 'run the tray message loop'
[System.Windows.Forms.Application]::Run()
} catch {
    if (-not $script:LxStartStep) { $script:LxStartStep = 'start the tray' }
    Show-LxStartupError -Step $script:LxStartStep -Reason $_.Exception.Message
} finally {
    if ($hk) { try { $hk.Dispose() } catch {} }
    if ($tray) { try { $tray.Visible = $false; $tray.Dispose() } catch {} }
    try { $mutex.ReleaseMutex() } catch {}
    try { $mutex.Dispose() } catch {}
}


