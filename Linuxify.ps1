<#
.SYNOPSIS Tray "Linuxify": liga/desliga o modo Linux. Ctrl+Alt+L alterna.
  Sem parametro = abre o tray. -Action On|Off|Toggle|TrayAutostartOn|TrayAutostartOff = executa e sai.
#>
[CmdletBinding()]
param([ValidateSet('', 'On', 'Off', 'Toggle', 'TrayAutostartOn', 'TrayAutostartOff')][string]$Action = '')
$Data  = Join-Path $env:LOCALAPPDATA 'Linuxify'
$State = Join-Path $Data 'state.txt'
$Run   = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$WtSet = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
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

function Enable-Linux {
    foreach ($a in $Apps) {
        $exe = Find-Exe $a
        if (-not $exe) { continue }
        if ($exe -like 'shell:*') { Set-ItemProperty $Run $a.Key "explorer.exe $exe" } else { Set-ItemProperty $Run $a.Key "`"$exe`"" }
        if (-not (Get-Process $a.Proc -ErrorAction SilentlyContinue)) { if ($exe -like 'shell:*') { Start-Process explorer.exe -ArgumentList $exe } else { Start-Process $exe } }
    }
    Start-Zebar
    Set-Windhawk $true
    $lx = Join-Path $Data 'wt.settings.linux.json'
    if ((Test-Path $lx) -and (Test-Path $WtSet)) { Copy-Item $lx $WtSet -Force }
    Set-Content $State 'on'
}
function Disable-Linux {
    foreach ($a in $Apps) { Remove-ItemProperty $Run $a.Key -ErrorAction SilentlyContinue }
    Remove-ItemProperty $Run 'Linuxify.Zebar' -ErrorAction SilentlyContinue
    if (Get-Command glazewm -ErrorAction SilentlyContinue) { & glazewm command wm-exit 2>$null }
    foreach ($p in 'glazewm', 'glazewm-watcher', 'zebar') { Get-Process $p -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue }
    # Windhawk fica sempre ligado
    $orig = Join-Path $Data 'wt.settings.original.json'
    if ((Test-Path $orig) -and (Test-Path $WtSet)) {
        if (-not (Test-Path (Join-Path $Data 'wt.settings.linux.json'))) { Copy-Item $WtSet (Join-Path $Data 'wt.settings.linux.json') }
        Copy-Item $orig $WtSet -Force
    }
    # (Windhawk sempre ligado, sem restart do explorer)
    Set-Content $State 'off'
}
function Set-TrayAutostart([bool]$On) {
    if ($On) { $exe = Join-Path $Data 'Linuxify.exe'; if (Test-Path $exe) { Set-ItemProperty $Run 'Linuxify' "`"$exe`""; return }; Set-ItemProperty $Run 'Linuxify' "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -STA -File `"$Data\Linuxify.ps1`"" }
    else { Remove-ItemProperty $Run 'Linuxify' -ErrorAction SilentlyContinue }
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
if (-not $mutex.WaitOne(0)) { return }
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition @'
using System; using System.Runtime.InteropServices; using System.Windows.Forms;
public class HotkeyWindow : NativeWindow, IDisposable {
  [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr h, int id, uint mod, uint vk);
  [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr h, int id);
  public event EventHandler Pressed;
  public bool Ok;
  public HotkeyWindow(uint mod, uint vk) { CreateHandle(new CreateParams()); Ok = RegisterHotKey(Handle, 1, mod, vk); }
  protected override void WndProc(ref Message m) { if (m.Msg == 0x0312 && Pressed != null) Pressed(this, EventArgs.Empty); base.WndProc(ref m); }
  public void Dispose() { UnregisterHotKey(Handle, 1); DestroyHandle(); }
}
'@

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

$tray = New-Object System.Windows.Forms.NotifyIcon
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
Update-Ui
$tray.Visible = $true
if (-not $hk.Ok) { $tray.ShowBalloonTip(3000, 'Linuxify', (T 'Ctrl+Alt+L is already in use; use the icon.'), 'Warning') }
# Transparencia: reaplica regras salvas (inicio + janelas novas) se 'Aplicar ao iniciar'
$tmT = New-Object System.Windows.Forms.Timer; $tmT.Interval = 1500
$tmT.add_Tick({ try { $c = Get-LxTransp; if ($c.ApplyOnStart -ne $false) { Invoke-LxTranspRules $c }; Invoke-LxTranspManual } catch {} }); $tmT.Start()
# Reaplica estado salvo no boot (autostart dos apps ja cuida; isto garante coerencia)
function Start-LxDesktop { $dc = Join-Path $Data 'desktop.json'; if ((Test-Path $dc) -and ((Get-Content $dc -Raw | ConvertFrom-Json).Enabled)) { Start-Process powershell -WindowStyle Hidden -ArgumentList "-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Data\LinuxifyDesktop.ps1`"" } }
try { Start-LxDesktop } catch {}
[System.Windows.Forms.Application]::Run()
$hk.Dispose(); $tray.Dispose(); $mutex.ReleaseMutex()


