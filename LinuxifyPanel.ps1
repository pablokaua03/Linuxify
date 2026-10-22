<#
.SYNOPSIS Linuxify - mini painel (Geral / Terminal / Excecoes GlazeWM / Transparencia).
  -Shot <pasta> = abre, tira print de cada aba e fecha (teste).
  Arquivo ASCII-only de proposito (PS 5.1 le .ps1 sem BOM como ANSI). Tudo que ele grava e UTF-8 sem BOM.
#>
[CmdletBinding()]
param([string]$Shot = '', [string]$Tab = '')
$ErrorActionPreference = 'Continue'
$Data   = Join-Path $env:LOCALAPPDATA 'Linuxify'
$Tray   = Join-Path $Data 'Linuxify.ps1'
$Run    = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$WtSet  = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
$WtLx   = Join-Path $Data 'wt.settings.linux.json'
$WtOrig = Join-Path $Data 'wt.settings.original.json'
$Glz    = Join-Path $HOME '.glzr\glazewm\config.yaml'
$FfDir  = Join-Path $HOME '.config\fastfetch'
$FfCfg  = Join-Path $FfDir 'config.jsonc'
$Prefs  = Join-Path $Data 'panel.json'
$Utf8   = New-Object System.Text.UTF8Encoding($false)

function Write-NoBom([string]$Path, [string]$Text) { [IO.File]::WriteAllText($Path, $Text, $Utf8) }
function Read-Text([string]$Path) { [IO.File]::ReadAllText($Path) }   # remove BOM se tiver
function Backup-File([string]$Path) {
    if (-not (Test-Path $Path)) { return $null }
    $dir = Join-Path $Data ('backup\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Force $dir | Out-Null
    $dst = Join-Path $dir (($Path -replace '[:\\/]', '_'))
    Copy-Item $Path $dst -Force
    Add-Content (Join-Path $Data 'backups.txt') "$Path|$dst"
    $dst
}

# ---------------- ferramentas ----------------
$Tools = [ordered]@{
  GlazeWM  = @{ Id='glzr-io.glazewm'; Proc='glazewm'; Exe="$env:ProgramFiles\glzr.io\GlazeWM\glazewm.exe"; Run='Linuxify.GlazeWM'; Note='Gerenciador de janelas em tiles' }
  Zebar    = @{ Id='glzr-io.zebar'; Proc='zebar'; Exe="$env:ProgramFiles\glzr.io\Zebar\zebar.exe"; Run='Linuxify.Zebar'; Note='Barra superior' }
  Windhawk = @{ Id='RamenSoftware.Windhawk'; Proc='windhawk'; Exe="$env:ProgramFiles\Windhawk\windhawk.exe"; Run=''; Note='Mods do Windows (sempre ligado)' }
  Terminal = @{ Id='Microsoft.WindowsTerminal'; Proc=''; Exe=''; Run=''; Note='Tema do Windows Terminal + banner ASCII' }
}
function Test-Installed($n) {
    if ($n -eq 'Terminal') { return [bool](Get-AppxPackage Microsoft.WindowsTerminal -ErrorAction SilentlyContinue) }
    Test-Path $Tools[$n].Exe
}
function Test-ThemeApplied {
    if (-not (Test-Path $WtSet)) { return $false }
    try { $o = Read-Text $WtSet | ConvertFrom-Json; [bool]($o.profiles.defaults.colorScheme) -and ((Test-Path $WtLx) -and ((Get-FileHash $WtSet).Hash -eq (Get-FileHash $WtLx).Hash -or $o.profiles.defaults.colorScheme -ne $null)) } catch { $false }
}
function Test-On($n) {
    if ($n -eq 'Terminal') {
        if (-not ((Test-Path $WtSet) -and (Test-Path $WtLx))) { return $false }
        return (Get-FileHash $WtSet).Hash -eq (Get-FileHash $WtLx).Hash
    }
    [bool](Get-Process $Tools[$n].Proc -ErrorAction SilentlyContinue)
}
function Set-Tool($n, [bool]$On) {
    $t = $Tools[$n]
    switch ($n) {
      'Terminal' {
        if (-not (Test-Path $WtSet)) { return }
        if ($On) { if (Test-Path $WtLx) { Backup-File $WtSet | Out-Null; Copy-Item $WtLx $WtSet -Force } }
        else {
            if ((Test-On 'Terminal') -eq $false -and (Test-Path $WtSet)) { }
            elseif (-not (Test-Path $WtLx)) { Copy-Item $WtSet $WtLx }
            if (Test-Path $WtOrig) { Backup-File $WtSet | Out-Null; Copy-Item $WtOrig $WtSet -Force }
        }
      }
      'Windhawk' {
        $svc = Get-Service -Name 'Windhawk' -ErrorAction SilentlyContinue
        if ($On) {
            if ($svc -and $svc.Status -ne 'Running') { Start-Process sc.exe -ArgumentList 'start Windhawk' -Verb RunAs -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue }
            if (-not (Get-Process windhawk -ErrorAction SilentlyContinue) -and (Test-Path $t.Exe)) { Start-Process $t.Exe -ArgumentList '-tray-only' }
        } else {
            Get-Process windhawk -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            if ($svc -and $svc.Status -eq 'Running') { Start-Process sc.exe -ArgumentList 'stop Windhawk' -Verb RunAs -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue }
        }
      }
      default {
        if ($On) {
            if (-not (Test-Path $t.Exe)) { return }
            Set-ItemProperty $Run $t.Run "`"$($t.Exe)`""
            if (-not (Get-Process $t.Proc -ErrorAction SilentlyContinue)) { Start-Process $t.Exe }
            # wm-exit do GlazeWM derruba o Zebar; religa se ele estava no autostart
            if ($n -eq 'GlazeWM' -and (Get-ItemProperty $Run -Name 'Linuxify.Zebar' -ErrorAction SilentlyContinue)) { Start-Sleep 3; if (-not (Get-Process zebar -ErrorAction SilentlyContinue)) { Start-Process $Tools.Zebar.Exe } }
        } else {
            Remove-ItemProperty $Run $t.Run -ErrorAction SilentlyContinue
            if ($n -eq 'GlazeWM') { $cli = Get-Command glazewm -ErrorAction SilentlyContinue; if ($cli) { & $cli.Source command wm-exit 2>$null | Out-Null; Start-Sleep -Milliseconds 800 } ; Get-Process glazewm-watcher -ErrorAction SilentlyContinue | Stop-Process -Force }
            Get-Process $t.Proc -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        }
      }
    }
}
function Invoke-Winget($n, [string]$Verb) {
    $id = $Tools[$n].Id
    Start-Process powershell -ArgumentList "-NoProfile -NoExit -Command winget $Verb --id $id -e"
}

# ---------------- GlazeWM excecoes ----------------
$BeginMark = '  # Excecoes (Linuxify painel)'
function Get-Exclusions {
    $list = @()
    if (-not (Test-Path $Glz)) { return $list }
    $lines = (Read-Text $Glz) -split "\r?\n"
    $zone = ''
    foreach ($l in $lines) {
        if ($l -match '^\s*# Jogos \(Linuxify\)') { $zone = 'Jogos (scan)'; continue }
        if ($l -match '^\s*# Excecoes \(Linuxify painel\)') { $zone = 'Painel'; continue }
        if ($zone -and $l -match '^\s*- commands:' -and $l -notmatch 'ignore') { $zone = '' }
        if ($zone -and $l -match '^\s*#') { $zone = '' }
        if ($zone -eq 'Jogos (scan)' -and $l -match "window_process:\s*\{\s*regex:\s*'\^\((.*)\)\$'") { foreach ($p in $Matches[1] -split '\|') { $list += [pscustomobject]@{ Name=$p; Src='Jogos (scan)' } } }
        elseif ($zone -eq 'Painel' -and $l -match "window_process:\s*\{\s*equals:\s*'(.*)'") { $list += [pscustomobject]@{ Name=$Matches[1]; Src='Painel' } }
        if ($zone -and $l -match '^\s*- commands:' -and $zone -eq 'Jogos (scan)' -and $list.Count -gt 0 -and $l -match 'ignore') { }
    }
    $list
}
function Save-PanelExclusions([string[]]$Names) {
    $raw = Read-Text $Glz
    $nl = if ($raw -match "`r`n") { "`r`n" } else { "`n" }
    $lines = [System.Collections.Generic.List[string]]($raw -split "\r?\n")
    # tira bloco antigo do painel
    $i = $lines.FindIndex([Predicate[string]]{ param($s) $s -match '^\s*# Excecoes \(Linuxify painel\)' })
    if ($i -ge 0) {
        $j = $i + 1
        while ($j -lt $lines.Count -and $lines[$j] -notmatch '^\s*- commands:') { $j++ }   # ate o "- commands"
        $j++
        while ($j -lt $lines.Count -and $lines[$j] -match '^\s{4,}') { $j++ }               # corpo do item
        $lines.RemoveRange($i, $j - $i)
    }
    if ($Names.Count -gt 0) {
        $wr = $lines.FindIndex([Predicate[string]]{ param($s) $s -match '^window_rules:' })
        if ($wr -lt 0) { throw 'window_rules: nao encontrado no config.yaml' }
        $blk = @($BeginMark, "  - commands: ['ignore']", '    match:')
        foreach ($n in $Names) { $blk += "      - window_process: { equals: '$($n -replace "'", "''")' }" }
        $lines.InsertRange($wr + 1, [string[]]$blk)
    }
    $bak = Backup-File $Glz
    Write-NoBom $Glz (($lines -join $nl))
    $cli = Get-Command glazewm -ErrorAction SilentlyContinue
    if ($cli -and (Get-Process glazewm -ErrorAction SilentlyContinue)) { & $cli.Source command wm-reload-config 2>$null | Out-Null }
    $bak
}

# ---------------- Terminal ----------------
$Schemes = @{
 'Catppuccin Mocha' = @{ name='Catppuccin Mocha'; cursorColor='#F5E0DC'; selectionBackground='#585B70'; background='#1E1E2E'; foreground='#CDD6F4'; black='#45475A'; red='#F38BA8'; green='#A6E3A1'; yellow='#F9E2AF'; blue='#89B4FA'; purple='#F5C2E7'; cyan='#94E2D5'; white='#BAC2DE'; brightBlack='#585B70'; brightRed='#F38BA8'; brightGreen='#A6E3A1'; brightYellow='#F9E2AF'; brightBlue='#89B4FA'; brightPurple='#F5C2E7'; brightCyan='#94E2D5'; brightWhite='#A6ADC8' }
 'Dracula'          = @{ name='Dracula'; cursorColor='#F8F8F2'; selectionBackground='#44475A'; background='#282A36'; foreground='#F8F8F2'; black='#21222C'; red='#FF5555'; green='#50FA7B'; yellow='#F1FA8C'; blue='#BD93F9'; purple='#FF79C6'; cyan='#8BE9FD'; white='#F8F8F2'; brightBlack='#6272A4'; brightRed='#FF6E6E'; brightGreen='#69FF94'; brightYellow='#FFFFA5'; brightBlue='#D6ACFF'; brightPurple='#FF92DF'; brightCyan='#A4FFFF'; brightWhite='#FFFFFF' }
 'Tokyo Night'      = @{ name='Tokyo Night'; cursorColor='#C0CAF5'; selectionBackground='#33467C'; background='#1A1B26'; foreground='#C0CAF5'; black='#15161E'; red='#F7768E'; green='#9ECE6A'; yellow='#E0AF68'; blue='#7AA2F7'; purple='#BB9AF7'; cyan='#7DCFFF'; white='#A9B1D6'; brightBlack='#414868'; brightRed='#F7768E'; brightGreen='#9ECE6A'; brightYellow='#E0AF68'; brightBlue='#7AA2F7'; brightPurple='#BB9AF7'; brightCyan='#7DCFFF'; brightWhite='#C0CAF5' }
 'Gruvbox Dark'     = @{ name='Gruvbox Dark'; cursorColor='#EBDBB2'; selectionBackground='#665C54'; background='#282828'; foreground='#EBDBB2'; black='#282828'; red='#CC241D'; green='#98971A'; yellow='#D79921'; blue='#458588'; purple='#B16286'; cyan='#689D6A'; white='#A89984'; brightBlack='#928374'; brightRed='#FB4934'; brightGreen='#B8BB26'; brightYellow='#FABD2F'; brightBlue='#83A598'; brightPurple='#D3869B'; brightCyan='#8EC07C'; brightWhite='#EBDBB2' }
}
function Set-Prop($obj, $name, $val) { if ($obj.PSObject.Properties[$name]) { $obj.$name = $val } else { $obj | Add-Member -NotePropertyName $name -NotePropertyValue $val } }
function Apply-Terminal($p) {
    if (-not (Test-Path $WtSet)) { throw 'settings.json do Windows Terminal nao encontrado' }
    if (-not (Test-Path $WtOrig)) { Copy-Item $WtSet $WtOrig }       # guarda original 1x
    $bak = Backup-File $WtSet
    $o = Read-Text $WtSet | ConvertFrom-Json
    $sc = [pscustomobject]$Schemes[$p.Scheme]
    if (-not $o.PSObject.Properties['schemes']) { Set-Prop $o 'schemes' @() }
    $o.schemes = @(@($o.schemes | Where-Object { $_.name -ne $p.Scheme }) + $sc)
    if (-not $o.profiles.PSObject.Properties['defaults']) { Set-Prop $o.profiles 'defaults' ([pscustomobject]@{}) }
    $d = $o.profiles.defaults
    Set-Prop $d 'colorScheme' $p.Scheme
    Set-Prop $d 'font' ([pscustomobject]@{ face = $p.Font; size = [int]$p.Size })
    Set-Prop $d 'opacity' ([int]$p.Opacity)
    Set-Prop $d 'useAcrylic' ([bool]$p.Acrylic)
    $json = $o | ConvertTo-Json -Depth 32
    Write-NoBom $WtSet $json
    Write-NoBom $WtLx $json                                           # tray usa essa versao no modo Linux
    # banner -> logo do fastfetch (o resto do perfil vem do fastfetch/starship)
    if ($p.Banner.Trim()) {
        New-Item -ItemType Directory -Force $FfDir | Out-Null
        Write-NoBom (Join-Path $FfDir 'banner.txt') ($p.Banner -replace "`r`n", "`n")
        if (Test-Path $FfCfg) {
            $ffo = Join-Path $Data 'fastfetch.config.original.jsonc'
            if (-not (Test-Path $ffo)) { Copy-Item $FfCfg $ffo }
            Backup-File $FfCfg | Out-Null
            $c = [System.Drawing.ColorTranslator]::FromHtml($p.AsciiColor)
            $t = Read-Text $FfCfg
            $t = $t -replace '"source":\s*"[^"]*"', '"source": "~/.config/fastfetch/banner.txt"'
            $t = $t -replace '"1":\s*"[^"]*"', ('"1": "38;2;{0};{1};{2}"' -f $c.R, $c.G, $c.B)
            Write-NoBom $FfCfg $t
        }
    }
    Write-NoBom $Prefs ($p | ConvertTo-Json)
    $bak
}
function Restore-Terminal {
    if (-not (Test-Path $WtOrig)) { throw 'sem backup original (wt.settings.original.json)' }
    Backup-File $WtSet | Out-Null
    Copy-Item $WtOrig $WtSet -Force
    $ffo = Join-Path $Data 'fastfetch.config.original.jsonc'
    if ((Test-Path $ffo) -and (Test-Path $FfCfg)) { Backup-File $FfCfg | Out-Null; Copy-Item $ffo $FfCfg -Force }
}

# ---------------- UI ----------------
try { Add-Type -Namespace Lx -Name Dpi -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();' -ErrorAction SilentlyContinue; [Lx.Dpi]::SetProcessDPIAware() | Out-Null } catch {}
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
if (-not ('LxToggle' -as [type])) {
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
using System; using System.Drawing; using System.Drawing.Drawing2D; using System.Windows.Forms;
public class LxToggle : Control {
  bool _on; public bool On { get { return _on; } set { _on = value; Invalidate(); } }
  public event EventHandler Flipped;
  public LxToggle() { SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.SupportsTransparentBackColor, true); Size = new Size(40, 22); Cursor = Cursors.Hand; }
  protected override void OnClick(EventArgs e) { _on = !_on; Invalidate(); if (Flipped != null) Flipped(this, e); base.OnClick(e); }
  protected override void OnPaint(PaintEventArgs e) {
    var g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias; g.Clear(Parent != null ? Parent.BackColor : BackColor);
    int h = Height - 1, w = Width - 1;
    using (var p = new GraphicsPath()) { p.AddArc(0, 0, h, h, 90, 180); p.AddArc(w - h, 0, h, h, 270, 180); p.CloseFigure();
      using (var b = new SolidBrush(_on ? Color.FromArgb(203,166,247) : Color.FromArgb(88,91,112))) g.FillPath(b, p); }
    int k = h - 6; int x = _on ? w - k - 3 : 3;
    using (var b = new SolidBrush(_on ? Color.FromArgb(30,30,46) : Color.FromArgb(205,214,244))) g.FillEllipse(b, x, 3, k, k);
  }
}
'@
}
. (Join-Path $Data 'LinuxifyAlpha.ps1')
[System.Windows.Forms.Application]::EnableVisualStyles()
function C($hex) { [System.Drawing.ColorTranslator]::FromHtml($hex) }
$cBase=C '#1e1e2e'; $cMantle=C '#181825'; $cCrust=C '#11111b'; $cS0=C '#313244'; $cS1=C '#45475a'; $cS2=C '#585b70'
$cText=C '#cdd6f4'; $cSub=C '#a6adc8'; $cOv=C '#9399b2'; $cMauve=C '#cba6f7'; $cGreen=C '#a6e3a1'; $cRed=C '#f38ba8'; $cYellow=C '#f9e2af'
$fUi = New-Object System.Drawing.Font('Segoe UI', 9.5)
$fB  = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
$fH  = New-Object System.Drawing.Font('Segoe UI Semibold', 14)
$fS  = New-Object System.Drawing.Font('Segoe UI', 8.5)
$monoName = @('JetBrainsMono Nerd Font','JetBrains Mono','Cascadia Mono','Consolas') | Where-Object { (New-Object System.Drawing.Font($_, 9)).Name -eq $_ } | Select-Object -First 1
$fM  = New-Object System.Drawing.Font($monoName, 9)

function New-Btn($text, $kind = '') {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text; $b.FlatStyle = 'Flat'; $b.FlatAppearance.BorderSize = 0; $b.Font = $fUi; $b.AutoSize = $true; $b.Padding = '6,0,6,0'; $b.Cursor = 'Hand'
    switch ($kind) { 'pr' { $b.BackColor = $cMauve; $b.ForeColor = $cBase; $b.Font = $fB } 'dg' { $b.BackColor = C '#4a2b3a'; $b.ForeColor = $cRed } default { $b.BackColor = $cS1; $b.ForeColor = $cText } }
    $b
}
function New-Lbl($text, $font = $fUi, $color = $cText) { $l = New-Object System.Windows.Forms.Label; $l.Text = $text; $l.Font = $font; $l.ForeColor = $color; $l.AutoSize = $true; $l.BackColor = 'Transparent'; $l }
function New-Card($x, $y, $w, $h) { $p = New-Object System.Windows.Forms.Panel; $p.SetBounds($x, $y, $w, $h); $p.BackColor = $cS0; $p }

$form = New-Object System.Windows.Forms.Form
$form.AutoScaleDimensions = New-Object System.Drawing.SizeF(96, 96); $form.AutoScaleMode = 'Dpi'
$form.Text = 'Linuxify'; $form.ClientSize = '780,640'; $form.BackColor = $cBase; $form.ForeColor = $cText; $form.Font = $fUi
$form.FormBorderStyle = 'FixedSingle'; $form.MaximizeBox = $false; $form.StartPosition = 'CenterScreen'
$ico = [LxAlpha]::Logo(32, $cMauve)
$form.Icon = [System.Drawing.Icon]::FromHandle($ico.GetHicon())
try { Add-Type -Namespace Lx -Name Dwm -MemberDefinition '[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr h, int a, ref int v, int s);' -ErrorAction SilentlyContinue } catch {}
$form.add_HandleCreated({ try { $v = 1; [Lx.Dwm]::DwmSetWindowAttribute($form.Handle, 20, [ref]$v, 4) | Out-Null; $c = 0x00251818; [Lx.Dwm]::DwmSetWindowAttribute($form.Handle, 35, [ref]$c, 4) | Out-Null } catch {} })

$side = New-Object System.Windows.Forms.Panel; $side.SetBounds(0, 0, 180, 640); $side.BackColor = $cMantle; $form.Controls.Add($side)
$pages = @{}; $navs = @{}
function Show-Tab($k) {
    foreach ($n in $pages.Keys) { $pages[$n].Visible = ($n -eq $k); $navs[$n].BackColor = if ($n -eq $k) { $cS0 } else { $cMantle }; $navs[$n].ForeColor = if ($n -eq $k) { $cMauve } else { $cSub }; $navs[$n].Font = $fUi }
    if ($k -eq 'geral') { Update-Geral } elseif ($k -eq 'exc') { Load-Exc } elseif ($k -eq 'transp') { Fill-Transp }
}
$y = 14
foreach ($t in @(@('geral', '  Geral'), @('term', '  Terminal'), @('exc', '  Excecoes GlazeWM'), @('transp', '  Transparencia'))) {
    $b = New-Object System.Windows.Forms.Button; $b.Text = $t[1]; $b.TextAlign = 'MiddleLeft'; $b.FlatStyle = 'Flat'; $b.FlatAppearance.BorderSize = 0; $b.SetBounds(8, $y, 164, 36); $b.Tag = $t[0]; $b.Cursor = 'Hand'
    $b.add_Click({ Show-Tab $this.Tag }); $side.Controls.Add($b); $navs[$t[0]] = $b; $y += 42
    $p = New-Object System.Windows.Forms.Panel; $p.SetBounds(180, 0, 600, 640); $p.BackColor = $cBase; $p.Visible = $false; $form.Controls.Add($p); $pages[$t[0]] = $p
}
$ver = New-Lbl 'Linuxify' $fS $cOv; $ver.Location = '16,610'; $side.Controls.Add($ver)

# ===== Geral =====
$pg = $pages['geral']
$cm = New-Card 20 18 560 70; $pg.Controls.Add($cm)
$l = New-Lbl 'Modo Linux' $fH; $l.Location = '14,10'; $cm.Controls.Add($l)
$l = New-Lbl 'Liga tudo de uma vez  -  atalho Ctrl+Alt+L' $fS $cOv; $l.Location = '16,42'; $cm.Controls.Add($l)
$tgMode = New-Object LxToggle; $tgMode.Size = '54,28'; $tgMode.Location = '490,21'; $cm.Controls.Add($tgMode)
$tgMode.add_Flipped({ $form.Cursor = 'WaitCursor'; & powershell -NoProfile -ExecutionPolicy Bypass -File $Tray -Action $(if ($tgMode.On) { 'On' } else { 'Off' }); $form.Cursor = 'Default'; Update-Geral })
$l = New-Lbl 'FERRAMENTAS' $fS $cSub; $l.Location = '22,100'; $pg.Controls.Add($l)
$ct = New-Card 20 120 560 300; $pg.Controls.Add($ct)
$rows = @{}; $ry = 6
$icons = @{ GlazeWM = 'W'; Zebar = 'B'; Windhawk = 'H'; Terminal = '>' }
foreach ($n in $Tools.Keys) {
    $ic = New-Lbl $icons[$n] $fB $cMauve; $ic.AutoSize = $false; $ic.SetBounds(12, $ry + 14, 34, 34); $ic.BackColor = $cS1; $ic.TextAlign = 'MiddleCenter'; $ct.Controls.Add($ic)
    $nm = New-Lbl $(if ($n -eq 'Terminal') { 'Windows Terminal (tema)' } else { $n }) $fB; $nm.Location = "56,$($ry + 10)"; $ct.Controls.Add($nm)
    $nt = New-Lbl $Tools[$n].Note $fS $cOv; $nt.Location = "57,$($ry + 38)"; $ct.Controls.Add($nt)
    $st = New-Lbl '' $fS $cGreen; $st.AutoSize = $false; $st.TextAlign = 'MiddleCenter'; $st.SetBounds(300, $ry + 21, 74, 20); $ct.Controls.Add($st)
    $tg = New-Object LxToggle; $tg.Location = "384,$($ry + 20)"; $tg.Tag = $n; $ct.Controls.Add($tg)
    $tg.add_Flipped({ $n = $this.Tag; $form.Cursor = 'WaitCursor'; Set-Tool $n $this.On; Start-Sleep -Milliseconds 700; $form.Cursor = 'Default'; Update-Geral })
    $bt = New-Btn 'Instalar'; $bt.Padding = '0,0,0,0'; $bt.AutoSize = $false; $bt.SetBounds(434, $ry + 17, 116, 28); $bt.Tag = $n; $ct.Controls.Add($bt)
    $bt.add_Click({
        $n = $this.Tag
        if ($n -eq 'Terminal' -and (Test-Installed 'Terminal')) {
            if ([System.Windows.Forms.MessageBox]::Show('Remover o tema e voltar o settings.json original do Terminal?', 'Linuxify', 'YesNo', 'Question') -eq 'Yes') { try { Restore-Terminal } catch { [System.Windows.Forms.MessageBox]::Show("$_") } }
        } elseif (Test-Installed $n) {
            if ([System.Windows.Forms.MessageBox]::Show("Desinstalar $n via winget?", 'Linuxify', 'YesNo', 'Warning') -eq 'Yes') { Set-Tool $n $false; Invoke-Winget $n 'uninstall' }
        } else { Invoke-Winget $n 'install' }
        Update-Geral
    })
    if ($ry -lt 220) { $sep = New-Object System.Windows.Forms.Panel; $sep.SetBounds(12, $ry + 66, 536, 1); $sep.BackColor = $cS1; $ct.Controls.Add($sep) }
    $rows[$n] = @{ St = $st; Tg = $tg; Bt = $bt }; $ry += 72
}
$l = New-Lbl 'Instalar/Desinstalar usa o winget (abre uma janela pra voce acompanhar).' $fS $cOv; $l.Location = '22,428'; $pg.Controls.Add($l)
$cbBoot = New-Object System.Windows.Forms.CheckBox; $cbBoot.Text = 'Iniciar com o Windows'; $cbBoot.AutoSize = $true; $cbBoot.Location = '22,456'; $cbBoot.ForeColor = $cText; $pg.Controls.Add($cbBoot)
$cbBoot.add_Click({ & powershell -NoProfile -ExecutionPolicy Bypass -File $Tray -Action $(if ($cbBoot.Checked) { 'TrayAutostartOn' } else { 'TrayAutostartOff' }) })
$DeskCfg = Join-Path $Data 'desktop.json'
function Get-DeskSet { $d = [pscustomobject]@{ Enabled = $false; Corner = 'BottomRight'; Opacity = 85; Refresh = 45 }; if (Test-Path $DeskCfg) { try { $j = Get-Content $DeskCfg -Raw | ConvertFrom-Json; foreach ($p in $j.PSObject.Properties) { $d | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force } } catch {} }; $d }
function Save-DeskSet($c) { [IO.File]::WriteAllText($DeskCfg, ($c | ConvertTo-Json), (New-Object System.Text.UTF8Encoding($false))) }
function Stop-Desk { Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object CommandLine -like '*LinuxifyDesktop.ps1*' | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } }
function Start-Desk { Stop-Desk; Start-Process powershell -WindowStyle Hidden -ArgumentList "-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Data\LinuxifyDesktop.ps1`"" }
$cbDesk = New-Object System.Windows.Forms.CheckBox; $cbDesk.Text = 'Terminal na area de trabalho'; $cbDesk.AutoSize = $true; $cbDesk.Location = '22,484'; $cbDesk.ForeColor = $cText; $pg.Controls.Add($cbDesk)
$cbCorner = New-Object System.Windows.Forms.ComboBox; $cbCorner.DropDownStyle = 'DropDownList'; $cbCorner.FlatStyle = 'Flat'; $cbCorner.SetBounds(260, 482, 140, 24)
[void]$cbCorner.Items.AddRange([object[]]@('BottomRight', 'BottomLeft', 'TopRight', 'TopLeft')); $pg.Controls.Add($cbCorner)
$ds0 = Get-DeskSet; $cbDesk.Checked = [bool]$ds0.Enabled; $cbCorner.SelectedItem = [string]$ds0.Corner; if ($cbCorner.SelectedIndex -lt 0) { $cbCorner.SelectedIndex = 0 }
$cbDesk.add_Click({ $c = Get-DeskSet; $c.Enabled = $cbDesk.Checked; Save-DeskSet $c; if ($cbDesk.Checked) { Start-Desk } else { Stop-Desk } })
$cbCorner.add_SelectedIndexChanged({ $c = Get-DeskSet; if ($c.Corner -ne [string]$cbCorner.SelectedItem) { $c.Corner = [string]$cbCorner.SelectedItem; Save-DeskSet $c } })
$bAll = New-Btn 'Desinstalar tudo...' 'dg'; $bAll.Location = '20,590'; $pg.Controls.Add($bAll)
$bAll.add_Click({ if ([System.Windows.Forms.MessageBox]::Show('Desfazer tudo e restaurar as configs originais?', 'Linuxify', 'YesNo', 'Warning') -eq 'Yes') { Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$Data\uninstall.ps1`" -Force"; $form.Close() } })
$bDir = New-Btn 'Abrir pasta'; $bDir.AutoSize = $false; $bDir.SetBounds(400, 590, 180, 32); $pg.Controls.Add($bDir)
$bDir.add_Click({ Start-Process explorer.exe $Data })
function Update-Geral {
    $tgMode.On = (Test-Path (Join-Path $Data 'state.txt')) -and ((Get-Content (Join-Path $Data 'state.txt') -Raw).Trim() -eq 'on')
    foreach ($n in $Tools.Keys) {
        $r = $rows[$n]; $inst = Test-Installed $n; $on = Test-On $n
        $r.Tg.On = $on; $r.Tg.Enabled = $inst
        if (-not $inst) { $r.St.Text = 'Ausente'; $r.St.ForeColor = $cOv; $r.St.BackColor = $cS1 }
        elseif ($on) { $r.St.Text = $(if ($n -eq 'Terminal') { 'Aplicado' } else { 'Rodando' }); $r.St.ForeColor = $cGreen; $r.St.BackColor = C '#3a4a45' }
        else { $r.St.Text = $(if ($n -eq 'Terminal') { 'Original' } else { 'Parado' }); $r.St.ForeColor = $cYellow; $r.St.BackColor = C '#4a463a' }
        if ($n -eq 'Terminal') { $r.Bt.Text = $(if ($inst) { 'Tirar tema' } else { 'Instalar' }) } else { $r.Bt.Text = $(if ($inst) { 'Desinstalar' } else { 'Instalar' }) }
        if ($inst) { $r.Bt.BackColor = C '#4a2b3a'; $r.Bt.ForeColor = $cRed } else { $r.Bt.BackColor = $cMauve; $r.Bt.ForeColor = $cBase }
    }
    $cbBoot.Checked = [bool](Get-ItemProperty $Run -Name 'Linuxify' -ErrorAction SilentlyContinue)
}

# ===== Terminal =====
$pt = $pages['term']
$pref = @{ Scheme = 'Catppuccin Mocha'; Font = $monoName; Size = 11; Opacity = 85; Acrylic = $true; AsciiColor = '#cba6f7'; Banner = "  _     _`n | |   (_)_ __  _   ___  __`n | |   | | '_ \| | | \ \/ /`n | |___| | | | | |_| |>  <`n |_____|_|_| |_|\__,_/_/\_\" }
if (Test-Path $WtSet) { try { $d = (Read-Text $WtSet | ConvertFrom-Json).profiles.defaults; if ($d.colorScheme -and $Schemes[$d.colorScheme]) { $pref.Scheme = $d.colorScheme }; if ($d.font.face) { $pref.Font = $d.font.face }; if ($d.font.size) { $pref.Size = $d.font.size }; if ($d.opacity) { $pref.Opacity = $d.opacity }; if ($null -ne $d.useAcrylic) { $pref.Acrylic = $d.useAcrylic } } catch {} }
if (Test-Path $Prefs) { try { $sv = Read-Text $Prefs | ConvertFrom-Json; foreach ($k in 'AsciiColor', 'Banner') { if ($sv.$k) { $pref[$k] = $sv.$k } } } catch {} }
$l = New-Lbl 'BANNER ASCII' $fS $cSub; $l.Location = '20,16'; $pt.Controls.Add($l)
$tbB = New-Object System.Windows.Forms.TextBox; $tbB.Multiline = $true; $tbB.ScrollBars = 'Both'; $tbB.WordWrap = $false; $tbB.SetBounds(20, 36, 270, 170); $tbB.BackColor = $cMantle; $tbB.ForeColor = $cText; $tbB.BorderStyle = 'FixedSingle'; $tbB.Font = $fM; $tbB.Text = ($pref.Banner -replace "\r?\n", "`r`n"); $pt.Controls.Add($tbB)
$l = New-Lbl 'Cole seu ASCII aqui - o resto e montado sozinho' $fS $cOv; $l.Location = '20,210'; $pt.Controls.Add($l)
$l = New-Lbl 'PREVIA' $fS $cSub; $l.Location = '310,16'; $pt.Controls.Add($l)
$rtP = New-Object System.Windows.Forms.RichTextBox; $rtP.SetBounds(310, 36, 270, 170); $rtP.ReadOnly = $true; $rtP.BorderStyle = 'None'; $rtP.Font = $fM; $rtP.WordWrap = $false; $rtP.ScrollBars = 'None'; $pt.Controls.Add($rtP)
$cc = New-Card 20 236 560 200; $pt.Controls.Add($cc)
$l = New-Lbl 'Esquema de cores' $fS $cSub; $l.Location = '14,12'; $cc.Controls.Add($l)
$cbS = New-Object System.Windows.Forms.ComboBox; $cbS.DropDownStyle = 'DropDownList'; $cbS.FlatStyle = 'Flat'; $cbS.BackColor = $cMantle; $cbS.ForeColor = $cText; $cbS.SetBounds(14, 32, 250, 24); [void]$cbS.Items.AddRange([object[]]@($Schemes.Keys | Sort-Object)); $cbS.SelectedItem = $pref.Scheme; $cc.Controls.Add($cbS)
$l = New-Lbl 'Cor do ASCII' $fS $cSub; $l.Location = '290,12'; $cc.Controls.Add($l)
$sw = @(); $sx = 290
$tbC = New-Object System.Windows.Forms.TextBox; $tbC.BackColor = $cMantle; $tbC.ForeColor = $cText; $tbC.BorderStyle = 'FixedSingle'; $tbC.Font = $fM; $tbC.SetBounds(450, 33, 90, 22); $tbC.Text = $pref.AsciiColor
foreach ($hx in '#cba6f7', '#89b4fa', '#a6e3a1', '#fab387', '#f38ba8') { $s = New-Object System.Windows.Forms.Panel; $s.SetBounds($sx, 33, 22, 22); $s.BackColor = C $hx; $s.Tag = $hx; $s.Cursor = 'Hand'; $s.add_Click({ $tbC.Text = $this.Tag }); $cc.Controls.Add($s); $sx += 30 }
$cc.Controls.Add($tbC)
$l = New-Lbl 'Fonte' $fS $cSub; $l.Location = '14,70'; $cc.Controls.Add($l)
$cbF = New-Object System.Windows.Forms.ComboBox; $cbF.DropDownStyle = 'DropDownList'; $cbF.FlatStyle = 'Flat'; $cbF.BackColor = $cMantle; $cbF.ForeColor = $cText; $cbF.SetBounds(14, 90, 250, 24)
$fams = (New-Object System.Drawing.Text.InstalledFontCollection).Families | ForEach-Object Name | Where-Object { $_ -match 'Mono|Nerd|Code|Consolas|Courier|Cascadia|Hack|Fira|Iosevka' }
[void]$cbF.Items.AddRange([object[]]@($fams)); if (-not $cbF.Items.Contains($pref.Font)) { [void]$cbF.Items.Add($pref.Font) }; $cbF.SelectedItem = $pref.Font; $cc.Controls.Add($cbF)
$nuS = New-Object System.Windows.Forms.NumericUpDown; $nuS.Minimum = 6; $nuS.Maximum = 36; $nuS.Value = [int]$pref.Size; $nuS.SetBounds(272, 90, 56, 24); $nuS.BackColor = $cMantle; $nuS.ForeColor = $cText; $cc.Controls.Add($nuS)
$l = New-Lbl 'Transparencia' $fUi; $l.Location = '14,136'; $cc.Controls.Add($l)
$trO = New-Object System.Windows.Forms.TrackBar; $trO.Minimum = 30; $trO.Maximum = 100; $trO.TickStyle = 'None'; $trO.SetBounds(120, 132, 380, 30); $trO.Value = [Math]::Min(100, [Math]::Max(30, [int]$pref.Opacity)); $trO.BackColor = $cS0; $cc.Controls.Add($trO)
$lO = New-Lbl "$($trO.Value)%" $fB; $lO.Location = '506,134'; $cc.Controls.Add($lO); $trO.add_ValueChanged({ $lO.Text = "$($trO.Value)%" })
$l = New-Lbl 'Efeito acrilico' $fUi; $l.Location = '14,170'; $cc.Controls.Add($l)
$tgA = New-Object LxToggle; $tgA.Location = '500,166'; $tgA.On = [bool]$pref.Acrylic; $cc.Controls.Add($tgA)
function Update-Preview {
    $sc = $Schemes[[string]$cbS.SelectedItem]; if (-not $sc) { return }
    $rtP.BackColor = C $sc.background; $rtP.Clear()
    $col = try { C $tbC.Text } catch { $cMauve }
    $rtP.SelectionColor = $col; $rtP.AppendText(($tbB.Text -replace "`r", '') + "`n")
    $rtP.SelectionColor = C $sc.green; $rtP.AppendText($env:USERNAME); $rtP.SelectionColor = C $sc.foreground; $rtP.AppendText('@')
    $rtP.SelectionColor = C $sc.blue; $rtP.AppendText($env:COMPUTERNAME.ToLower()); $rtP.SelectionColor = C $sc.yellow; $rtP.AppendText(' ~ ')
    $rtP.SelectionColor = C $sc.purple; $rtP.AppendText('> '); $rtP.SelectionColor = C $sc.foreground; $rtP.AppendText('_')
}
$tbB.add_TextChanged({ Update-Preview }); $cbS.add_SelectedIndexChanged({ Update-Preview }); $tbC.add_TextChanged({ Update-Preview })
$bRes = New-Btn 'Restaurar original' 'dg'; $bRes.Location = '20,590'; $pt.Controls.Add($bRes)
$bRes.add_Click({ if ([System.Windows.Forms.MessageBox]::Show('Voltar o settings.json original do Windows Terminal (e o logo original do fastfetch)?', 'Linuxify', 'YesNo', 'Question') -eq 'Yes') { try { Restore-Terminal; [System.Windows.Forms.MessageBox]::Show('Original restaurado.', 'Linuxify') | Out-Null } catch { [System.Windows.Forms.MessageBox]::Show("Erro: $_", 'Linuxify') | Out-Null } } })
$bAp = New-Btn 'Aplicar' 'pr'; $bAp.Location = '500,590'; $pt.Controls.Add($bAp)
$bAp.add_Click({
    try { $b = Apply-Terminal ([pscustomobject]@{ Scheme = [string]$cbS.SelectedItem; Font = [string]$cbF.SelectedItem; Size = [int]$nuS.Value; Opacity = $trO.Value; Acrylic = $tgA.On; AsciiColor = $tbC.Text; Banner = $tbB.Text })
          [System.Windows.Forms.MessageBox]::Show("Aplicado. Backup: $b", 'Linuxify') | Out-Null } catch { [System.Windows.Forms.MessageBox]::Show("Erro: $_", 'Linuxify') | Out-Null }
})

# ===== Excecoes =====
$pe = $pages['exc']
$l = New-Lbl 'Excecoes do GlazeWM' $fH; $l.Location = '18,12'; $pe.Controls.Add($l)
$l = New-Lbl 'Apps aqui nao sao reorganizados pelo GlazeWM. "Jogos (scan)" = regra de jogos.' $fS $cOv; $l.Location = '20,44'; $pe.Controls.Add($l)
$tbQ = New-Object System.Windows.Forms.TextBox; $tbQ.SetBounds(20, 70, 440, 26); $tbQ.BackColor = $cMantle; $tbQ.ForeColor = $cText; $tbQ.BorderStyle = 'FixedSingle'; $pe.Controls.Add($tbQ)
$lv = New-Object System.Windows.Forms.ListView; $lv.View = 'Details'; $lv.FullRowSelect = $true; $lv.HeaderStyle = 'None'; $lv.BorderStyle = 'None'; $lv.SetBounds(20, 106, 560, 466); $lv.BackColor = $cS0; $lv.ForeColor = $cText; $lv.Font = $fM
[void]$lv.Columns.Add('Processo', 360); [void]$lv.Columns.Add('Origem', 180); $pe.Controls.Add($lv)
$script:exc = @()
function Load-Exc { $script:exc = @(Get-Exclusions); Fill-Exc }
function Fill-Exc {
    $lv.BeginUpdate(); $lv.Items.Clear()
    foreach ($e in $script:exc) { if ($tbQ.Text -and $e.Name -notlike "*$($tbQ.Text)*") { continue }; $it = New-Object System.Windows.Forms.ListViewItem("$($e.Name).exe"); [void]$it.SubItems.Add($e.Src); $it.Tag = $e; if ($e.Src -ne 'Painel') { $it.ForeColor = $cSub }; [void]$lv.Items.Add($it) }
    $lv.EndUpdate()
}
$tbQ.add_TextChanged({ Fill-Exc })
function Save-Exc([string[]]$names) {
    try { $b = Save-PanelExclusions $names; Load-Exc; return $b } catch { [System.Windows.Forms.MessageBox]::Show("Erro: $_", 'Linuxify') | Out-Null }
}
function Add-Exc([string]$name) {
    $name = ($name.Trim() -replace '\.exe$', ''); if (-not $name) { return }
    if ($script:exc | Where-Object { $_.Name -ieq $name }) { return }
    Save-Exc (@($script:exc | Where-Object Src -eq 'Painel' | ForEach-Object Name) + $name) | Out-Null
}
$bAdd = New-Btn '+ Adicionar' 'pr'; $bAdd.AutoSize = $false; $bAdd.SetBounds(20, 590, 180, 32); $pe.Controls.Add($bAdd)
$bAdd.add_Click({ if ($tbQ.Text.Trim()) { Add-Exc $tbQ.Text; $tbQ.Text = '' } else { [System.Windows.Forms.MessageBox]::Show('Digite o nome do processo (ex: game.exe) na caixa de busca e clique de novo.', 'Linuxify') | Out-Null } })
$bPick = New-Btn '+ Janela aberta'; $bPick.AutoSize = $false; $bPick.SetBounds(208, 590, 190, 32); $pe.Controls.Add($bPick)
$bPick.add_Click({
    $cm2 = New-Object System.Windows.Forms.ContextMenuStrip
    Get-Process | Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle } | Sort-Object ProcessName -Unique | ForEach-Object { $mi = $cm2.Items.Add("$($_.ProcessName)  -  $($_.MainWindowTitle)"); $mi.Tag = $_.ProcessName; $mi.add_Click({ Add-Exc $this.Tag }) }
    $cm2.Show($bPick, 0, $bPick.Height)
})
$bDel = New-Btn 'Remover'; $bDel.AutoSize = $false; $bDel.SetBounds(406, 590, 174, 32); $pe.Controls.Add($bDel)
$bDel.add_Click({
    $sel = @($lv.SelectedItems | ForEach-Object { $_.Tag })
    if ($sel | Where-Object Src -ne 'Painel') { [System.Windows.Forms.MessageBox]::Show('Itens "Jogos (scan)" ficam na regra de jogos; edite pelo scan.', 'Linuxify') | Out-Null }
    $rm = @($sel | Where-Object Src -eq 'Painel' | ForEach-Object Name); if (-not $rm) { return }
    Save-Exc @($script:exc | Where-Object { $_.Src -eq 'Painel' -and $rm -notcontains $_.Name } | ForEach-Object Name) | Out-Null
})
$bRel = New-Btn 'Recarregar'; $bRel.AutoSize = $false; $bRel.SetBounds(470, 68, 110, 28); $pe.Controls.Add($bRel); $bRel.add_Click({ Load-Exc })

# ===== Transparencia =====
$pa = $pages['transp']; $script:tcfg = Get-LxTransp
$l = New-Lbl 'Transparencia de janelas' $fH; $l.Location = '18,12'; $pa.Controls.Add($l)
$l = New-Lbl 'Escolha uma janela, ajuste a opacidade (ao vivo). Salve como regra pro app.' $fS $cOv; $l.Location = '20,44'; $pa.Controls.Add($l)
$lvT = New-Object System.Windows.Forms.ListView; $lvT.View = 'Details'; $lvT.FullRowSelect = $true; $lvT.MultiSelect = $false; $lvT.HideSelection = $false; $lvT.HeaderStyle = 'Nonclickable'; $lvT.BorderStyle = 'None'; $lvT.SetBounds(20, 70, 560, 250); $lvT.BackColor = $cS0; $lvT.ForeColor = $cText; $lvT.Font = $fUi
[void]$lvT.Columns.Add('Janela', 330); [void]$lvT.Columns.Add('Processo', 140); [void]$lvT.Columns.Add('Opac.', 70); $pa.Controls.Add($lvT)
function Fill-Transp {
    $lvT.BeginUpdate(); $lvT.Items.Clear()
    foreach ($w in [LxAlpha]::List()) {
        $a = [LxAlpha]::Get($w.Handle); $pc = if ($a -lt 0) { '100%' } else { "$([int][Math]::Round($a * 100 / 255))%" }
        $it = New-Object System.Windows.Forms.ListViewItem($w.Title); [void]$it.SubItems.Add($w.Proc); [void]$it.SubItems.Add($pc); $it.Tag = $w
        if ($pc -ne '100%') { $it.ForeColor = $cMauve }; [void]$lvT.Items.Add($it)
    }
    $lvT.EndUpdate()
}
$ca = New-Card 20 330 560 160; $pa.Controls.Add($ca)
$lSel = New-Lbl 'Nenhuma janela selecionada' $fB; $lSel.AutoSize = $false; $lSel.SetBounds(14, 10, 530, 22); $ca.Controls.Add($lSel)
$l = New-Lbl 'Opacidade' $fUi; $l.Location = '14,46'; $ca.Controls.Add($l)
$trT = New-Object System.Windows.Forms.TrackBar; $trT.Minimum = 20; $trT.Maximum = 100; $trT.Value = 100; $trT.TickStyle = 'None'; $trT.AutoSize = $false; $trT.SetBounds(100, 42, 390, 40); $trT.BackColor = $cS0; $ca.Controls.Add($trT)
$lT = New-Lbl '100%' $fB; $lT.Location = '500,44'; $ca.Controls.Add($lT)
$script:tSel = $null
function Get-SelWin { if ($lvT.SelectedItems.Count) { $lvT.SelectedItems[0].Tag } else { $null } }
$lvT.add_SelectedIndexChanged({
    $w = Get-SelWin; if (-not $w) { return }
    $script:tSel = $w; $lSel.Text = "$($w.Proc)  -  $($w.Title)"
    $a = [LxAlpha]::Get($w.Handle); $script:tMute = $true; $trT.Value = if ($a -lt 0) { 100 } else { [Math]::Max(20, [int][Math]::Round($a * 100 / 255)) }; $script:tMute = $false; $lT.Text = "$($trT.Value)%"
})
$trT.add_ValueChanged({
    $lT.Text = "$($trT.Value)%"; if ($script:tMute -or -not $script:tSel) { return }
    if ($trT.Value -ge 100) { [LxAlpha]::Restore($script:tSel.Handle) } else { [void][LxAlpha]::Set($script:tSel.Handle, $trT.Value) }
    if ($lvT.SelectedItems.Count) { $lvT.SelectedItems[0].SubItems[2].Text = "$($trT.Value)%" }
})
$bRule = New-Btn 'Salvar regra do app'; $bRule.AutoSize = $false; $bRule.SetBounds(14, 100, 190, 40); $ca.Controls.Add($bRule)
$bRule.add_Click({
    if (-not $script:tSel) { return }; $p = $script:tSel.Proc
    $script:tcfg.Rules = @($script:tcfg.Rules | Where-Object { $_.Process -ine $p }) + [pscustomobject]@{ Process = $p; Opacity = $trT.Value }
    Save-LxTransp $script:tcfg; Fill-Rules
})
$bOne = New-Btn 'Restaurar'; $bOne.AutoSize = $false; $bOne.SetBounds(214, 100, 140, 40); $ca.Controls.Add($bOne)
$bOne.add_Click({ if ($script:tSel) { [LxAlpha]::Restore($script:tSel.Handle); $script:tMute = $true; $trT.Value = 100; $script:tMute = $false; $lT.Text = '100%'; Fill-Transp } })
$l = New-Lbl 'Regras salvas (por app):' $fS $cOv; $l.Location = '20,498'; $pa.Controls.Add($l)
$cbR = New-Object System.Windows.Forms.ComboBox; $cbR.DropDownStyle = 'DropDownList'; $cbR.FlatStyle = 'Flat'; $cbR.SetBounds(180, 495, 170, 24); $pa.Controls.Add($cbR)
$bREd = New-Btn 'Usar % atual'; $bREd.AutoSize = $false; $bREd.SetBounds(358, 492, 110, 30); $pa.Controls.Add($bREd)
$bRDel = New-Btn 'Remover' 'dg'; $bRDel.AutoSize = $false; $bRDel.SetBounds(474, 492, 106, 30); $pa.Controls.Add($bRDel)
function Fill-Rules {
    $cbR.Items.Clear(); foreach ($r in @($script:tcfg.Rules)) { [void]$cbR.Items.Add("$($r.Process)  $($r.Opacity)%") }
    if ($cbR.Items.Count) { $cbR.SelectedIndex = 0; $cbR.Enabled = $true } else { [void]$cbR.Items.Add('(nenhuma)'); $cbR.SelectedIndex = 0; $cbR.Enabled = $false }
    $bREd.Enabled = $cbR.Enabled; $bRDel.Enabled = $cbR.Enabled
}
function Get-SelRule { if (-not $cbR.Enabled -or $cbR.SelectedIndex -lt 0) { return $null }; @($script:tcfg.Rules)[$cbR.SelectedIndex] }
$cbR.add_SelectedIndexChanged({ $r = Get-SelRule; if ($r) { $script:tMute = $true; $trT.Value = [Math]::Max(20, [Math]::Min(100, [int]$r.Opacity)); $script:tMute = $false; $lT.Text = "$($trT.Value)%" } })
$bREd.add_Click({ $r = Get-SelRule; if (-not $r) { return }; $r.Opacity = $trT.Value; Save-LxTransp $script:tcfg; Fill-Rules; foreach ($w in [LxAlpha]::List()) { if ($w.Proc -ieq $r.Process) { if ($r.Opacity -ge 100) { [LxAlpha]::Restore($w.Handle) } else { [void][LxAlpha]::Set($w.Handle, [int]$r.Opacity) } } }; Fill-Transp })
$bRDel.add_Click({ $r = Get-SelRule; if (-not $r) { return }; $script:tcfg.Rules = @($script:tcfg.Rules | Where-Object { $_.Process -ine $r.Process }); Save-LxTransp $script:tcfg; foreach ($w in [LxAlpha]::List()) { if ($w.Proc -ieq $r.Process -and [LxAlpha]::Get($w.Handle) -ge 0) { [LxAlpha]::Restore($w.Handle) } }; Fill-Rules; Fill-Transp })
$cbTS = New-Object System.Windows.Forms.CheckBox; $cbTS.Text = 'Aplicar regras automaticamente (janelas novas e reabertas)'; $cbTS.AutoSize = $true; $cbTS.Location = '22,546'; $cbTS.ForeColor = $cText; $cbTS.Checked = $script:tcfg.ApplyOnStart; $pa.Controls.Add($cbTS)
$cbTS.add_CheckedChanged({ $script:tcfg.ApplyOnStart = $cbTS.Checked; Save-LxTransp $script:tcfg })
$bAct = New-Btn '+ Janela ativa'; $bAct.AutoSize = $false; $bAct.SetBounds(20, 584, 190, 40); $pa.Controls.Add($bAct)
$bAct.add_Click({
    $bAct.Text = 'Clique na janela... 3'; $form.Refresh()
    foreach ($n in 2, 1, 0) { for ($i = 0; $i -lt 10; $i++) { Start-Sleep -Milliseconds 100; [System.Windows.Forms.Application]::DoEvents() }; $bAct.Text = "Clique na janela... $n"; $form.Refresh() }
    $h = [LxAlpha]::GetForegroundWindow(); $bAct.Text = '+ Janela ativa'
    Fill-Transp; foreach ($it in $lvT.Items) { if ($it.Tag.Handle -eq $h) { $it.Selected = $true; $it.EnsureVisible() } }
    $form.Activate()
})
$bTRel = New-Btn 'Recarregar'; $bTRel.AutoSize = $false; $bTRel.SetBounds(218, 584, 140, 40); $pa.Controls.Add($bTRel); $bTRel.add_Click({ Fill-Transp })
$bAll = New-Btn 'Restaurar todas' 'dg'; $bAll.AutoSize = $false; $bAll.SetBounds(400, 584, 180, 40); $pa.Controls.Add($bAll)
$bAll.add_Click({
    foreach ($w in [LxAlpha]::List()) { if ([LxAlpha]::Get($w.Handle) -ge 0) { [LxAlpha]::Restore($w.Handle) } }
    $script:tcfg.Rules = @(); Save-LxTransp $script:tcfg; Fill-Rules; Fill-Transp; $script:tMute = $true; $trT.Value = 100; $script:tMute = $false; $lT.Text = '100%'
})
Fill-Rules

Update-Preview
Show-Tab $(if ($Tab) { $Tab } else { 'geral' })
if ($Shot) {
    New-Item -ItemType Directory -Force $Shot | Out-Null
    $form.TopMost = $true
    $form.add_Shown({
        foreach ($k in 'geral', 'term', 'exc', 'transp') {
            Show-Tab $k; $form.Activate(); $form.Refresh(); [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 600; [System.Windows.Forms.Application]::DoEvents()
            $r = $form.Bounds; $bmp = New-Object System.Drawing.Bitmap $r.Width, $r.Height
            $form.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle 0, 0, $r.Width, $r.Height))
            $bmp.Save((Join-Path $Shot "panel-$k.png"), [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
        }
        $form.Close()
    })
}
[void]$form.ShowDialog()
