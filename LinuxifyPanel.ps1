<#
.SYNOPSIS Linuxify - mini painel (Geral / Terminal / Excecoes GlazeWM / Transparencia).
  -Shot <folder> = open, screenshot every tab and close (test). -Lang <code> = force a language (en, pt-BR, es, ru).
  Arquivo ASCII-only de proposito (PS 5.1 le .ps1 sem BOM como ANSI). Tudo que ele grava e UTF-8 sem BOM.
#>
[CmdletBinding()]
param([string]$Shot = '', [string]$Tab = '', [string]$Lang = '')
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
$FfLogo = Join-Path $FfDir 'logo.txt'          # banner atual (fastfetch + widget)
$FfDef  = Join-Path $FfDir 'logo-default.txt'  # banner padrao do Linuxify
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
  GlazeWM  = @{ Id='glzr-io.glazewm'; Proc='glazewm'; Exe="$env:ProgramFiles\glzr.io\GlazeWM\glazewm.exe"; Run='Linuxify.GlazeWM'; Note='Tiling window manager' }
  Zebar    = @{ Id='glzr-io.zebar'; Proc='zebar'; Exe="$env:ProgramFiles\glzr.io\Zebar\zebar.exe"; Run='Linuxify.Zebar'; Note='Top bar' }
  Windhawk = @{ Id='RamenSoftware.Windhawk'; Proc='windhawk'; Exe="$env:ProgramFiles\Windhawk\windhawk.exe"; Run=''; Note='Windows mods (always on)' }
  Terminal = @{ Id='Microsoft.WindowsTerminal'; Proc=''; Exe=''; Run=''; Note='Windows Terminal theme + ASCII banner' }
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
        Write-NoBom $FfLogo ($p.Banner -replace "`r`n", "`n")
        if (Test-Path $FfCfg) {
            $ffo = Join-Path $Data 'fastfetch.config.original.jsonc'
            if (-not (Test-Path $ffo)) { Copy-Item $FfCfg $ffo }
            Backup-File $FfCfg | Out-Null
            $c = [System.Drawing.ColorTranslator]::FromHtml($p.AsciiColor)
            $t = Read-Text $FfCfg
            $t = $t -replace '"source":\s*"[^"]*"', '"source": "~/.config/fastfetch/logo.txt"'
            $t = $t -replace '"1":\s*"[^"]*"', ('"1": "38;2;{0};{1};{2}"' -f $c.R, $c.G, $c.B)
            Write-NoBom $FfCfg $t
        }
    }
    if ($global:LxLang) { $p | Add-Member -NotePropertyName Lang -NotePropertyValue $global:LxLang -Force }
    Write-NoBom $Prefs ($p | ConvertTo-Json)
    $bak
}
function Restore-Terminal {
    if (-not (Test-Path $WtOrig)) { throw 'sem backup original (wt.settings.original.json)' }
    Backup-File $WtSet | Out-Null
    Copy-Item $WtOrig $WtSet -Force
    $ffo = Join-Path $Data 'fastfetch.config.original.jsonc'
    if ((Test-Path $ffo) -and (Test-Path $FfCfg)) { Backup-File $FfCfg | Out-Null; Copy-Item $ffo $FfCfg -Force }
    Restore-Banner
}
function Restore-Banner {
    if (-not (Test-Path $FfDef)) { return }
    if (Test-Path $FfLogo) { Backup-File $FfLogo | Out-Null }
    Copy-Item $FfDef $FfLogo -Force
    if (Test-Path $FfCfg) { $t = Read-Text $FfCfg; $t2 = $t -replace '"source":\s*"[^"]*"', '"source": "~/.config/fastfetch/logo.txt"'; if ($t2 -ne $t) { Backup-File $FfCfg | Out-Null; Write-NoBom $FfCfg $t2 } }
    if (Test-Path $Prefs) { try { $sv = Read-Text $Prefs | ConvertFrom-Json; $sv.PSObject.Properties.Remove('Banner'); Write-NoBom $Prefs ($sv | ConvertTo-Json) } catch {} }
}

# ---------------- UI ----------------
try { Add-Type -Namespace Lx -Name Dpi -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr v); [DllImport("user32.dll")] public static extern IntPtr MonitorFromPoint(System.Drawing.Point p, uint f); [DllImport("shcore.dll")] public static extern int GetDpiForMonitor(IntPtr m, int t, out uint x, out uint y);' -ReferencedAssemblies System.Drawing -ErrorAction SilentlyContinue } catch {}
$PerMon = $false; try { $PerMon = [Lx.Dpi]::SetProcessDpiAwarenessContext([IntPtr](-4)) } catch {}; if (-not $PerMon) { try { [Lx.Dpi]::SetProcessDPIAware() | Out-Null } catch {} }
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
if (-not ('LxGlass' -as [type])) {
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
using System; using System.Drawing; using System.Drawing.Drawing2D; using System.Drawing.Text; using System.Windows.Forms;
public static class LxG {
  public static GraphicsPath RR(RectangleF r, float rad) { var p = new GraphicsPath(); float d = Math.Min(rad * 2, Math.Min(r.Width, r.Height)); if (d < 1) { p.AddRectangle(r); return p; }
    p.AddArc(r.X, r.Y, d, d, 180, 90); p.AddArc(r.Right - d, r.Y, d, d, 270, 90); p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90); p.AddArc(r.X, r.Bottom - d, d, d, 90, 90); p.CloseFigure(); return p; }
  public static Color Mix(Color a, Color b, float t) { return Color.FromArgb((int)(a.R + (b.R - a.R) * t), (int)(a.G + (b.G - a.G) * t), (int)(a.B + (b.B - a.B) * t)); }
  public static bool Glass;
  public static Color Bg(Control c) { if (Glass) { var q = c.Parent; while (q != null && q.BackColor == Color.Transparent) q = q.Parent; if (q == null) return Color.FromArgb(0, 0, 0, 0); return Color.FromArgb(q is LxCard ? 170 : 0, q.BackColor); } var p = c.Parent; while (p != null && p.BackColor == Color.Transparent) p = p.Parent; return p != null ? p.BackColor : SystemColors.Control; }
  public static Color Fill(Color c, int a) { return Glass ? Color.FromArgb(a, c) : c; }
  public static void Text(Graphics g, string t, Font f, Rectangle r, Color c, bool center) {
    if (!Glass) { var fl = TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine | (center ? TextFormatFlags.HorizontalCenter : 0); TextRenderer.DrawText(g, t, f, r, c, fl); return; }
    g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
    using (var sf = new StringFormat(StringFormatFlags.NoWrap)) using (var b = new SolidBrush(c)) { sf.LineAlignment = StringAlignment.Center; sf.Alignment = center ? StringAlignment.Center : StringAlignment.Near; sf.Trimming = StringTrimming.EllipsisCharacter; g.DrawString(t, f, b, r, sf); }
  }
}
public class LxToggle : Control {
  bool _on, _hov; public bool On { get { return _on; } set { _on = value; Invalidate(); } }
  public Color Accent = Color.FromArgb(203,166,247);
  public event EventHandler Flipped;
  public LxToggle() { SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true); Size = new Size(44, 24); Cursor = Cursors.Hand; }
  protected override void OnMouseEnter(EventArgs e) { _hov = true; Invalidate(); base.OnMouseEnter(e); }
  protected override void OnMouseLeave(EventArgs e) { _hov = false; Invalidate(); base.OnMouseLeave(e); }
  protected override void OnEnabledChanged(EventArgs e) { Invalidate(); base.OnEnabledChanged(e); }
  protected override void OnClick(EventArgs e) { _on = !_on; Invalidate(); if (Flipped != null) Flipped(this, e); base.OnClick(e); }
  protected override void OnPaint(PaintEventArgs e) {
    var g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias; g.Clear(LxG.Bg(this));
    var r = new RectangleF(1, 1, Width - 3, Height - 3); float h = r.Height;
    Color track = _on ? Accent : Color.FromArgb(69,71,90); if (_hov && Enabled) track = LxG.Mix(track, Color.White, 0.12f); if (!Enabled) track = LxG.Mix(track, Color.FromArgb(30,30,46), 0.55f);
    using (var p = LxG.RR(r, h / 2)) using (var b = new SolidBrush(track)) g.FillPath(b, p);
    if (!_on) using (var p = LxG.RR(r, h / 2)) using (var pen = new Pen(Color.FromArgb(108,112,134), 1f)) g.DrawPath(pen, p);
    float k = h - 8; float x = _on ? r.Right - k - 4 : r.X + 4;
    using (var b = new SolidBrush(_on ? Color.FromArgb(30,30,46) : Color.FromArgb(186,194,222))) g.FillEllipse(b, x, r.Y + 4, k, k);
  }
}
public class LxCard : Panel {
  public int Radius = 12; public Color Border = Color.FromArgb(49,50,68);
  public LxCard() { SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true); }
  protected override void OnPaintBackground(PaintEventArgs e) {
    var g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias; g.Clear(LxG.Bg(this));
    using (var p = LxG.RR(new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f), Radius)) { using (var b = new SolidBrush(LxG.Fill(BackColor, 170))) g.FillPath(b, p); using (var pen = new Pen(LxG.Fill(LxG.Mix(BackColor, Color.White, 0.10f), 200))) g.DrawPath(pen, p); }
  }
}
public class LxButton : Button {
  bool _hov, _down; public int Radius = 8;
  public LxButton() { SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true); FlatStyle = FlatStyle.Flat; FlatAppearance.BorderSize = 0; Cursor = Cursors.Hand; }
  protected override void OnMouseEnter(EventArgs e) { _hov = true; Invalidate(); base.OnMouseEnter(e); }
  protected override void OnMouseLeave(EventArgs e) { _hov = false; _down = false; Invalidate(); base.OnMouseLeave(e); }
  protected override void OnMouseDown(MouseEventArgs e) { _down = true; Invalidate(); base.OnMouseDown(e); }
  protected override void OnMouseUp(MouseEventArgs e) { _down = false; Invalidate(); base.OnMouseUp(e); }
  public override Size GetPreferredSize(Size s) { var t = TextRenderer.MeasureText(Text, Font); return new Size(t.Width + 28 + Padding.Horizontal, Math.Max(32, t.Height + 14)); }
  protected override void OnPaint(PaintEventArgs e) {
    var g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias; g.Clear(LxG.Bg(this));
    Color c = BackColor; if (!Enabled) c = LxG.Mix(c, LxG.Bg(this), 0.5f); else if (_down) c = LxG.Mix(c, Color.Black, 0.12f); else if (_hov) c = LxG.Mix(c, Color.White, 0.12f);
    using (var p = LxG.RR(new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f), Radius)) using (var b = new SolidBrush(c)) g.FillPath(b, p);
    LxG.Text(g, Text, Font, ClientRectangle, Enabled ? ForeColor : LxG.Mix(ForeColor, c, 0.5f), true);
  }
}
public class LxPill : Label {
  public LxPill() { SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true); AutoSize = false; }
  protected override void OnPaint(PaintEventArgs e) {
    var g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias; g.Clear(LxG.Bg(this));
    var sz = TextRenderer.MeasureText(Text, Font); float w = Math.Min(Width - 1, sz.Width + 22); var r = new RectangleF(Width - 1 - w, (Height - 22) / 2f, w, 22);
    using (var p = LxG.RR(r, 11)) using (var b = new SolidBrush(BackColor)) g.FillPath(b, p);
    using (var b = new SolidBrush(ForeColor)) g.FillEllipse(b, r.X + 9, r.Y + 8, 6, 6);
    LxG.Text(g, Text, Font, Rectangle.Round(new RectangleF(r.X + 14, r.Y, r.Width - 16, r.Height)), ForeColor, true);
  }
}
public class LxNav : Control {
  bool _hov, _sel; public string Glyph = ""; public Font GlyphFont; public Color Accent = Color.FromArgb(203,166,247);
  public bool Selected { get { return _sel; } set { _sel = value; Invalidate(); } }
  public LxNav() { SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true); Cursor = Cursors.Hand; }
  protected override void OnMouseEnter(EventArgs e) { _hov = true; Invalidate(); base.OnMouseEnter(e); }
  protected override void OnMouseLeave(EventArgs e) { _hov = false; Invalidate(); base.OnMouseLeave(e); }
  protected override void OnPaint(PaintEventArgs e) {
    var g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias; g.Clear(LxG.Bg(this));
    if (_sel || _hov) using (var p = LxG.RR(new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f), 8)) using (var b = new SolidBrush(LxG.Fill(_sel ? Color.FromArgb(49,50,68) : Color.FromArgb(36,36,54), 200))) g.FillPath(b, p);
    if (_sel) using (var p = LxG.RR(new RectangleF(0, Height * 0.28f, 3.5f, Height * 0.44f), 1.5f)) using (var b = new SolidBrush(Accent)) g.FillPath(b, p);
    Color fc = _sel ? Color.FromArgb(205,214,244) : Color.FromArgb(166,173,200);
    if (GlyphFont != null) LxG.Text(g, Glyph, GlyphFont, new Rectangle(10, 0, 30, Height), _sel ? Accent : fc, true);
    LxG.Text(g, Text, Font, new Rectangle(46, 0, Width - 50, Height), fc, false);
  }
}
public class LxSlider : Control {
  int _min = 0, _max = 100, _val = 50; bool _drag, _hov;
  public int SmallChange = 1, LargeChange = 10; public string TickStyle = "None"; public Color Accent = Color.FromArgb(203,166,247);
  public event EventHandler ValueChanged;
  public int Minimum { get { return _min; } set { _min = value; if (_val < _min) _val = _min; Invalidate(); } }
  public int Maximum { get { return _max; } set { _max = value; if (_val > _max) _val = _max; Invalidate(); } }
  public int Value { get { return _val; } set { int v = Math.Max(_min, Math.Min(_max, value)); if (v != _val) { _val = v; Invalidate(); if (ValueChanged != null) ValueChanged(this, EventArgs.Empty); } } }
  public LxSlider() { SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw | ControlStyles.Selectable, true); Size = new Size(200, 28); Cursor = Cursors.Hand; TabStop = true; }
  float Pos() { return _max == _min ? 0 : (float)(_val - _min) / (_max - _min); }
  void SetFromX(int x) { float k = Height * 0.32f; float t = (x - k) / Math.Max(1f, Width - 2 * k); Value = _min + (int)Math.Round(Math.Max(0, Math.Min(1, t)) * (_max - _min)); }
  protected override void OnMouseDown(MouseEventArgs e) { Focus(); _drag = true; SetFromX(e.X); base.OnMouseDown(e); }
  protected override void OnMouseMove(MouseEventArgs e) { if (_drag) SetFromX(e.X); base.OnMouseMove(e); }
  protected override void OnMouseUp(MouseEventArgs e) { _drag = false; base.OnMouseUp(e); }
  protected override void OnMouseEnter(EventArgs e) { _hov = true; Invalidate(); base.OnMouseEnter(e); }
  protected override void OnMouseLeave(EventArgs e) { _hov = false; Invalidate(); base.OnMouseLeave(e); }
  protected override bool IsInputKey(Keys k) { return k == Keys.Left || k == Keys.Right || k == Keys.Up || k == Keys.Down || base.IsInputKey(k); }
  protected override void OnKeyDown(KeyEventArgs e) { if (e.KeyCode == Keys.Left || e.KeyCode == Keys.Down) Value -= SmallChange; else if (e.KeyCode == Keys.Right || e.KeyCode == Keys.Up) Value += SmallChange; else if (e.KeyCode == Keys.PageDown) Value -= LargeChange; else if (e.KeyCode == Keys.PageUp) Value += LargeChange; base.OnKeyDown(e); }
  protected override void OnPaint(PaintEventArgs e) {
    var g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias; g.Clear(LxG.Bg(this));
    float k = Height * 0.32f, cy = Height / 2f, x0 = k, x1 = Width - k, xv = x0 + (x1 - x0) * Pos();
    using (var p = LxG.RR(new RectangleF(x0, cy - 2.5f, x1 - x0, 5), 2.5f)) using (var b = new SolidBrush(Color.FromArgb(69,71,90))) g.FillPath(b, p);
    if (xv > x0) using (var p = LxG.RR(new RectangleF(x0, cy - 2.5f, xv - x0, 5), 2.5f)) using (var b = new SolidBrush(Enabled ? Accent : Color.FromArgb(88,91,112))) g.FillPath(b, p);
    float r = (_hov || _drag) ? k : k - 1.5f;
    using (var b = new SolidBrush(Color.FromArgb(205,214,244))) g.FillEllipse(b, xv - r, cy - r, 2 * r, 2 * r);
    using (var b = new SolidBrush(Enabled ? Accent : Color.FromArgb(88,91,112))) g.FillEllipse(b, xv - r * 0.45f, cy - r * 0.45f, r * 0.9f, r * 0.9f);
  }
}
public class LxCombo : ComboBox {
  public Color Border = Color.FromArgb(69,71,90), HiBack = Color.FromArgb(69,71,90);
  public LxCombo() { DrawMode = DrawMode.OwnerDrawFixed; DropDownStyle = ComboBoxStyle.DropDownList; FlatStyle = FlatStyle.Flat; ItemHeight = 20; }
  protected override void OnDrawItem(DrawItemEventArgs e) {
    if (e.Index < 0) return; bool sel = (e.State & DrawItemState.Selected) != 0 && (e.State & DrawItemState.ComboBoxEdit) == 0;
    using (var b = new SolidBrush(sel ? HiBack : BackColor)) e.Graphics.FillRectangle(b, e.Bounds);
    TextRenderer.DrawText(e.Graphics, GetItemText(Items[e.Index]), Font, new Rectangle(e.Bounds.X + 6, e.Bounds.Y, e.Bounds.Width - 8, e.Bounds.Height), ForeColor, TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine);
  }
  protected override void WndProc(ref Message m) {
    base.WndProc(ref m);
    if (m.Msg == 0xF || m.Msg == 0x133) {
      using (var g = Graphics.FromHwnd(Handle)) {
        g.SmoothingMode = SmoothingMode.AntiAlias; var r = ClientRectangle; g.Clear(LxG.Bg(this));
        using (var p = LxG.RR(new RectangleF(0.5f, 0.5f, r.Width - 1.5f, r.Height - 1.5f), 6)) { using (var b = new SolidBrush(LxG.Fill(BackColor, 220))) g.FillPath(b, p); using (var pen = new Pen(Focused ? Color.FromArgb(203,166,247) : Border)) g.DrawPath(pen, p); }
        LxG.Text(g, Text, Font, new Rectangle(8, 0, r.Width - 30, r.Height), Enabled ? ForeColor : Color.FromArgb(108,112,134), false);
        float cx = r.Width - 14, cy = r.Height / 2f;
        using (var pen = new Pen(Color.FromArgb(166,173,200), 1.6f)) g.DrawLines(pen, new[] { new PointF(cx - 4, cy - 2), new PointF(cx, cy + 2), new PointF(cx + 4, cy - 2) });
      }
    }
  }
}
public static class LxGlass {
  [System.Runtime.InteropServices.DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr h, int a, ref int v, int s);
  [System.Runtime.InteropServices.DllImport("dwmapi.dll")] static extern int DwmExtendFrameIntoClientArea(IntPtr h, ref MARGINS m);
  [System.Runtime.InteropServices.DllImport("user32.dll")] static extern int SetWindowCompositionAttribute(IntPtr h, ref WCAD d);
  struct MARGINS { public int l, r, t, b; }
  struct WCAD { public int Attr; public IntPtr Data; public int Size; }
  struct ACCENT { public int State, Flags, Color, Anim; }
  // returns 2 = Win11 backdrop, 1 = Win10 acrylic blur, 0 = none
  public static int Enable(IntPtr h, int tintAlpha) {
    int build = Environment.OSVersion.Version.Build;
    try {
      if (build >= 22523) { var m = new MARGINS { l = -1, r = -1, t = -1, b = -1 }; DwmExtendFrameIntoClientArea(h, ref m); int t = 3; DwmSetWindowAttribute(h, 38, ref t, 4); return 2; }
      if (build >= 17134) {
        var a = new ACCENT { State = 4, Flags = 2, Color = (tintAlpha << 24) | 0x2e1e1e, Anim = 0 };
        int sz = System.Runtime.InteropServices.Marshal.SizeOf(a); IntPtr p = System.Runtime.InteropServices.Marshal.AllocHGlobal(sz);
        System.Runtime.InteropServices.Marshal.StructureToPtr(a, p, false); var d = new WCAD { Attr = 19, Data = p, Size = sz }; SetWindowCompositionAttribute(h, ref d); System.Runtime.InteropServices.Marshal.FreeHGlobal(p); return 1; }
    } catch { }
    return 0;
  }
}
'@
}
. (Join-Path $Data 'LinuxifyAlpha.ps1')
$__lf = Join-Path $PSScriptRoot 'LinuxifyLang.ps1'; if (-not (Test-Path $__lf)) { $__lf = Join-Path $Data 'LinuxifyLang.ps1' }; . $__lf
if ($Lang) { Import-LxLang $Lang }
[System.Windows.Forms.Application]::EnableVisualStyles()
function C($hex) { [System.Drawing.ColorTranslator]::FromHtml($hex) }
$cBase=C '#1e1e2e'; $cMantle=C '#181825'; $cCrust=C '#11111b'; $cS0=C '#313244'; $cS1=C '#45475a'; $cS2=C '#585b70'
$cText=C '#cdd6f4'; $cSub=C '#a6adc8'; $cOv=C '#9399b2'; $cMauve=C '#cba6f7'; $cGreen=C '#a6e3a1'; $cRed=C '#f38ba8'; $cYellow=C '#f9e2af'
# glass (panel.json: Glass, GlassLevel). Win11: DWM acrylic backdrop; GDI colors are added on top of it, so darker = more glass.
$GlassOn = $true; $GlassLvl = 60
if (Test-Path $Prefs) { try { $gp0 = Read-Text $Prefs | ConvertFrom-Json; if ($null -ne $gp0.Glass) { $GlassOn = [bool]$gp0.Glass }; if ($gp0.GlassLevel) { $GlassLvl = [Math]::Max(20, [Math]::Min(100, [int]$gp0.GlassLevel)) } } catch {} }
$GlassCap = [Environment]::OSVersion.Version.Build -ge 17134
function Mix-C($a, $b, [double]$t) { [System.Drawing.Color]::FromArgb([int]($a.R + ($b.R - $a.R) * $t), [int]($a.G + ($b.G - $a.G) * $t), [int]($a.B + ($b.B - $a.B) * $t)) }
$cCard = C '#262637'
[LxG]::Glass = ($GlassOn -and $GlassCap -and [Environment]::OSVersion.Version.Build -ge 22523)
if ($GlassOn -and $GlassCap) { $gk = $GlassLvl / 100.0; $blk = [System.Drawing.Color]::Black; $cBase = Mix-C $cBase $blk $gk; $cMantle = Mix-C $cMantle $blk ($gk * 0.9); $cCard = Mix-C $cCard $blk ($gk * 0.5) }
$uiF = if ((New-Object System.Drawing.Font('Segoe UI Variable Text', 9)).Name -eq 'Segoe UI Variable Text') { 'Segoe UI Variable Text' } else { 'Segoe UI' }
$fUi = New-Object System.Drawing.Font($uiF, 9.5)
$fB  = New-Object System.Drawing.Font($uiF, 10, [System.Drawing.FontStyle]::Bold)
$fH  = New-Object System.Drawing.Font($uiF, 15, [System.Drawing.FontStyle]::Bold)
$fS  = New-Object System.Drawing.Font($uiF, 8.5)
$icF = @('Segoe Fluent Icons', 'Segoe MDL2 Assets') | Where-Object { (New-Object System.Drawing.Font($_, 9)).Name -eq $_ } | Select-Object -First 1
$fIc = if ($icF) { New-Object System.Drawing.Font($icF, 12) } else { $null }
$fIcB = if ($icF) { New-Object System.Drawing.Font($icF, 15) } else { $null }
$Assets = @((Join-Path $PSScriptRoot 'assets'), (Join-Path $Data 'assets')) | Where-Object { Test-Path $_ } | Select-Object -First 1
$LxVer = 'v0.2.1'
$monoName = @('JetBrainsMono Nerd Font','JetBrains Mono','Cascadia Mono','Consolas') | Where-Object { (New-Object System.Drawing.Font($_, 9)).Name -eq $_ } | Select-Object -First 1
$fM  = New-Object System.Drawing.Font($monoName, 9)

function New-Btn($text, $kind = '') {
    $b = New-Object LxButton
    $b.Text = $text; $b.Font = $fUi; $b.AutoSize = $true; $b.Padding = '6,0,6,0'
    switch ($kind) { 'pr' { $b.BackColor = $cMauve; $b.ForeColor = $cBase; $b.Font = $fB } 'dg' { $b.BackColor = C '#3a2a36'; $b.ForeColor = $cRed } default { $b.BackColor = $cS1; $b.ForeColor = $cText } }
    $b
}
function New-Lbl($text, $font = $fUi, $color = $cText) { $l = New-Object System.Windows.Forms.Label; $l.Text = $text; $l.Font = $font; $l.ForeColor = $color; $l.AutoSize = $true; $l.BackColor = 'Transparent'; $l }
function New-Card($x, $y, $w, $h) { $p = New-Object LxCard; $p.SetBounds($x, $y, $w, $h); $p.BackColor = $cCard; $p }

$form = New-Object System.Windows.Forms.Form
$form.AutoScaleMode = 'None'
$form.Text = 'Linuxify'; $form.ClientSize = '780,640'; $form.BackColor = $cBase; $form.ForeColor = $cText; $form.Font = $fUi
$form.FormBorderStyle = 'FixedSingle'; $form.MaximizeBox = $false; $form.StartPosition = 'CenterScreen'
if ($Assets -and (Test-Path (Join-Path $Assets 'linuxify.ico'))) { $form.Icon = New-Object System.Drawing.Icon((Join-Path $Assets 'linuxify.ico')) } else { $ico = [LxAlpha]::Logo(32, $cMauve); $form.Icon = [System.Drawing.Icon]::FromHandle($ico.GetHicon()) }
try { Add-Type -Namespace Lx -Name Dwm -MemberDefinition '[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr h, int a, ref int v, int s);' -ErrorAction SilentlyContinue } catch {}
$form.add_HandleCreated({ try { if ($GlassOn) { if ($GlassCap) { [void][LxGlass]::Enable($form.Handle, [int](255 * (1 - $GlassLvl / 100.0))) } else { $form.Opacity = 1 - 0.2 * ($GlassLvl / 100.0) } } $v = 1; [Lx.Dwm]::DwmSetWindowAttribute($form.Handle, 20, [ref]$v, 4) | Out-Null; $c = $(if ($GlassOn -and $GlassCap) { -2 } else { 0x00251818 }); [Lx.Dwm]::DwmSetWindowAttribute($form.Handle, 35, [ref]$c, 4) | Out-Null; $r = 2; [Lx.Dwm]::DwmSetWindowAttribute($form.Handle, 33, [ref]$r, 4) | Out-Null; $t = 0x00f4d6cd; [Lx.Dwm]::DwmSetWindowAttribute($form.Handle, 36, [ref]$t, 4) | Out-Null; $bd = 0x00443231; [Lx.Dwm]::DwmSetWindowAttribute($form.Handle, 34, [ref]$bd, 4) | Out-Null } catch {} })

$side = New-Object System.Windows.Forms.Panel; $side.SetBounds(0, 0, 180, 640); $side.BackColor = $cMantle; $form.Controls.Add($side)
$pbLogo = New-Object System.Windows.Forms.PictureBox; $pbLogo.SetBounds(16, 18, 40, 40); $pbLogo.SizeMode = 'Zoom'; $pbLogo.BackColor = $cMantle; if ($Assets) { $lp = Join-Path $Assets 'logo-64.png'; if (Test-Path $lp) { $pbLogo.Image = [System.Drawing.Image]::FromFile($lp) } }; $side.Controls.Add($pbLogo)
$l = New-Lbl 'Linuxify' (New-Object System.Drawing.Font($uiF, 13, [System.Drawing.FontStyle]::Bold)); $l.Location = '62,17'; $side.Controls.Add($l)
$l = New-Lbl $LxVer $fS $cOv; $l.Location = '64,41'; $side.Controls.Add($l)
$sep = New-Object System.Windows.Forms.Panel; $sep.SetBounds(16, 74, 148, 1); $sep.BackColor = $cS0; $side.Controls.Add($sep)
$pages = @{}; $navs = @{}
function Show-Tab($k) {
    foreach ($n in $pages.Keys) { $pages[$n].Visible = ($n -eq $k); $navs[$n].Selected = ($n -eq $k) }
    if ($k -eq 'geral') { Update-Geral } elseif ($k -eq 'exc') { Load-Exc } elseif ($k -eq 'transp') { Fill-Transp }
}
$y = 88
foreach ($t in @(@('geral', 'General', [char]0xE80F), @('term', 'Terminal', [char]0xE756), @('exc', 'Exceptions', [char]0xF0E2), @('transp', 'Transparency', [char]0xE790))) {
    $b = New-Object LxNav; $b.Text = (T $t[1]); $b.Glyph = [string]$t[2]; $b.GlyphFont = $fIc; $b.Font = $fUi; $b.BackColor = $cMantle; $b.SetBounds(10, $y, 160, 40); $b.Tag = $t[0]
    $b.add_Click({ Show-Tab $this.Tag }); $side.Controls.Add($b); $navs[$t[0]] = $b; $y += 44
    $p = New-Object System.Windows.Forms.Panel; $p.SetBounds(180, 0, 600, 640); $p.BackColor = $cBase; $p.Visible = $false; $form.Controls.Add($p); $pages[$t[0]] = $p
}


# ===== Geral =====
$pg = $pages['geral']
$cm = New-Card 20 18 560 70; $pg.Controls.Add($cm)
$l = New-Lbl (T 'Linux mode') $fH; $l.Location = '14,10'; $cm.Controls.Add($l)
$l = New-Lbl (T 'Turns everything on at once  -  shortcut Ctrl+Alt+L') $fS $cOv; $l.Location = '16,42'; $cm.Controls.Add($l)
$tgMode = New-Object LxToggle; $tgMode.Size = '56,30'; $tgMode.Location = '488,20'; $cm.Controls.Add($tgMode)
$tgMode.add_Flipped({ $form.Cursor = 'WaitCursor'; & powershell -NoProfile -ExecutionPolicy Bypass -File $Tray -Action $(if ($tgMode.On) { 'On' } else { 'Off' }); $form.Cursor = 'Default'; Update-Geral })
$l = New-Lbl (T 'TOOLS') $fS $cSub; $l.Location = '22,100'; $pg.Controls.Add($l)
$ct = New-Card 20 120 560 300; $pg.Controls.Add($ct)
$rows = @{}; $ry = 6
$icons = if ($fIcB) { @{ GlazeWM = [string][char]0xF0E2; Zebar = [string][char]0xE8A0; Windhawk = [string][char]0xE771; Terminal = [string][char]0xE756 } } else { @{ GlazeWM = 'W'; Zebar = 'B'; Windhawk = 'H'; Terminal = '>' } }
$icCol = @{ GlazeWM = $cMauve; Zebar = C '#89b4fa'; Windhawk = C '#fab387'; Terminal = $cGreen }
foreach ($n in $Tools.Keys) {
    $ic = New-Lbl $icons[$n] $(if ($fIcB) { $fIcB } else { $fB }) $icCol[$n]; $ic.AutoSize = $false; $ic.SetBounds(12, $ry + 14, 36, 36); $ic.BackColor = $cS0; $ic.TextAlign = 'MiddleCenter'; $ct.Controls.Add($ic)
    $nm = New-Lbl $(if ($n -eq 'Terminal') { (T 'Windows Terminal (theme)') } else { $n }) $fB; $nm.Location = "56,$($ry + 10)"; $ct.Controls.Add($nm)
    $nt = New-Lbl (T $Tools[$n].Note) $fS $cOv; $nt.Location = "57,$($ry + 38)"; $ct.Controls.Add($nt)
    $st = New-Object LxPill; $st.Font = $fS; $st.ForeColor = $cGreen; $st.BackColor = $ct.BackColor; $st.SetBounds(296, $ry + 19, 86, 26); $ct.Controls.Add($st)
    $tg = New-Object LxToggle; $tg.Location = "384,$($ry + 20)"; $tg.Tag = $n; $ct.Controls.Add($tg)
    $tg.add_Flipped({ $n = $this.Tag; $form.Cursor = 'WaitCursor'; Set-Tool $n $this.On; Start-Sleep -Milliseconds 700; $form.Cursor = 'Default'; Update-Geral })
    $bt = New-Btn (T 'Install'); $bt.Padding = '0,0,0,0'; $bt.AutoSize = $false; $bt.SetBounds(436, $ry + 18, 112, 30); $bt.Tag = $n; $ct.Controls.Add($bt)
    $bt.add_Click({
        $n = $this.Tag
        if ($n -eq 'Terminal' -and (Test-Installed 'Terminal')) {
            if ([System.Windows.Forms.MessageBox]::Show((T 'Remove the theme and restore the original Terminal settings.json?'), 'Linuxify', 'YesNo', 'Question') -eq 'Yes') { try { Restore-Terminal } catch { [System.Windows.Forms.MessageBox]::Show("$_") } }
        } elseif (Test-Installed $n) {
            if ([System.Windows.Forms.MessageBox]::Show(((T 'Uninstall {0} via winget?') -f $n), 'Linuxify', 'YesNo', 'Warning') -eq 'Yes') { Set-Tool $n $false; Invoke-Winget $n 'uninstall' }
        } else { Invoke-Winget $n 'install' }
        Update-Geral
    })
    if ($ry -lt 220) { $sep = New-Object System.Windows.Forms.Panel; $sep.SetBounds(12, $ry + 66, 536, 1); $sep.BackColor = $cS1; $ct.Controls.Add($sep) }
    $rows[$n] = @{ St = $st; Tg = $tg; Bt = $bt }; $ry += 72
}
$l = New-Lbl (T 'Install/Uninstall uses winget (opens a window so you can follow along).') $fS $cOv; $l.Location = '22,428'; $pg.Controls.Add($l)
$cbBoot = New-Object System.Windows.Forms.CheckBox; $cbBoot.Text = (T 'Start with Windows'); $cbBoot.AutoSize = $true; $cbBoot.Location = '22,456'; $cbBoot.ForeColor = $cText; $pg.Controls.Add($cbBoot)
$lLang = New-Lbl (T 'Language') $fS $cOv; $lLang.Location = '350,459'; $pg.Controls.Add($lLang)
$cbLang = New-Object LxCombo; $cbLang.DropDownStyle = 'DropDownList'; $cbLang.FlatStyle = 'Flat'; $cbLang.SetBounds(416, 455, 144, 24); $cbLang.BackColor = $cS0; $cbLang.ForeColor = $cText; $pg.Controls.Add($cbLang)
foreach ($k in $global:LxLangs.Keys) { [void]$cbLang.Items.Add($global:LxLangs[$k]) }
$cbLang.SelectedIndex = [Math]::Max(0, @($global:LxLangs.Keys).IndexOf($global:LxLang))
$cbLang.add_SelectedIndexChanged({
    $code = @($global:LxLangs.Keys)[$cbLang.SelectedIndex]; if ($code -eq $global:LxLang) { return }
    $sv = [pscustomobject]@{}; if (Test-Path $Prefs) { try { $sv = Read-Text $Prefs | ConvertFrom-Json } catch {} }
    $sv | Add-Member -NotePropertyName Lang -NotePropertyValue $code -Force; Write-NoBom $Prefs ($sv | ConvertTo-Json)
    # reopen the panel in the new language (tray picks it up on its next menu open)
    $self = Join-Path $Data 'LinuxifyPanel.ps1'; if (-not (Test-Path $self)) { $self = $PSCommandPath }
    Start-Process powershell -WindowStyle Hidden -ArgumentList "-NoProfile -STA -ExecutionPolicy Bypass -File `"$self`" -Tab geral"; $form.Close()
})
$cbBoot.add_Click({ & powershell -NoProfile -ExecutionPolicy Bypass -File $Tray -Action $(if ($cbBoot.Checked) { 'TrayAutostartOn' } else { 'TrayAutostartOff' }) })
$DeskCfg = Join-Path $Data 'desktop.json'
function Get-DeskSet { $d = [pscustomobject]@{ Enabled = $false; Corner = 'BottomRight'; Opacity = 85; Refresh = 45; Scale = 100 }; if (Test-Path $DeskCfg) { try { $j = Get-Content $DeskCfg -Raw | ConvertFrom-Json; foreach ($p in $j.PSObject.Properties) { $d | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force } } catch {} }; $d }
function Save-DeskSet($c) { [IO.File]::WriteAllText($DeskCfg, ($c | ConvertTo-Json), (New-Object System.Text.UTF8Encoding($false))) }
function Stop-Desk { Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object CommandLine -like '*LinuxifyDesktop.ps1*' | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } }
function Start-Desk { Stop-Desk; Start-Process powershell -WindowStyle Hidden -ArgumentList "-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Data\LinuxifyDesktop.ps1`"" }
$cbDesk = New-Object System.Windows.Forms.CheckBox; $cbDesk.Text = (T 'Terminal on the desktop'); $cbDesk.AutoSize = $true; $cbDesk.Location = '22,484'; $cbDesk.ForeColor = $cText; $pg.Controls.Add($cbDesk)
$cbCorner = New-Object LxCombo; $cbCorner.DropDownStyle = 'DropDownList'; $cbCorner.FlatStyle = 'Flat'; $cbCorner.SetBounds(260, 482, 140, 24); $cbCorner.BackColor = $cS0; $cbCorner.ForeColor = $cText
$CornerKeys = @('BottomRight', 'BottomLeft', 'TopRight', 'TopLeft'); $CornerText = @{ BottomRight = 'Bottom right'; BottomLeft = 'Bottom left'; TopRight = 'Top right'; TopLeft = 'Top left' }
[void]$cbCorner.Items.AddRange([object[]]@($CornerKeys | ForEach-Object { T $CornerText[$_] })); $pg.Controls.Add($cbCorner)
$ds0 = Get-DeskSet; $cbDesk.Checked = [bool]$ds0.Enabled; $cbCorner.SelectedIndex = [array]::IndexOf($CornerKeys, [string]$ds0.Corner); if ($cbCorner.SelectedIndex -lt 0) { $cbCorner.SelectedIndex = 0 }
$cbDesk.add_Click({ $c = Get-DeskSet; $c.Enabled = $cbDesk.Checked; Save-DeskSet $c; if ($cbDesk.Checked) { Start-Desk } else { Stop-Desk } })
$cbCorner.add_SelectedIndexChanged({ $c = Get-DeskSet; $k = $CornerKeys[$cbCorner.SelectedIndex]; if ($c.Corner -ne $k) { $c.Corner = $k; Save-DeskSet $c } })
$lSz = New-Lbl (T 'Size') $fS $cOv; $lSz.Location = '40,520'; $pg.Controls.Add($lSz)
$trSz = New-Object LxSlider; $trSz.Minimum = 60; $trSz.Maximum = 120; $trSz.SmallChange = 10; $trSz.LargeChange = 10; $trSz.TickStyle = 'None'; $trSz.AutoSize = $false; $trSz.SetBounds(110, 514, 290, 30); $trSz.BackColor = $pg.BackColor; $pg.Controls.Add($trSz)
$lSzV = New-Lbl '100%' $fS $cText; $lSzV.Location = '408,520'; $pg.Controls.Add($lSzV)
$trSz.Value = [Math]::Max(60, [Math]::Min(120, [int]$ds0.Scale)); $lSzV.Text = "$($trSz.Value)%"
$trSz.add_ValueChanged({ $lSzV.Text = "$($trSz.Value)%" })
$trSz.add_MouseUp({ $c = Get-DeskSet; if ([int]$c.Scale -ne $trSz.Value) { $c.Scale = $trSz.Value; Save-DeskSet $c } })
$trSz.add_KeyUp({ $c = Get-DeskSet; if ([int]$c.Scale -ne $trSz.Value) { $c.Scale = $trSz.Value; Save-DeskSet $c } })
$bAll = New-Btn (T 'Uninstall everything...') 'dg'; $bAll.Location = '20,590'; $pg.Controls.Add($bAll)
$bAll.add_Click({ if ([System.Windows.Forms.MessageBox]::Show((T 'Undo everything and restore the original configs?'), 'Linuxify', 'YesNo', 'Warning') -eq 'Yes') { Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$Data\uninstall.ps1`" -Force"; $form.Close() } })
$bDir = New-Btn (T 'Open folder'); $bDir.AutoSize = $false; $bDir.SetBounds(400, 590, 180, 32); $pg.Controls.Add($bDir)
$bDir.add_Click({ Start-Process explorer.exe $Data })
function Restart-Panel([string]$key, $val) {
    $sv = [pscustomobject]@{}; if (Test-Path $Prefs) { try { $sv = Read-Text $Prefs | ConvertFrom-Json } catch {} }
    $sv | Add-Member -NotePropertyName $key -NotePropertyValue $val -Force; Write-NoBom $Prefs ($sv | ConvertTo-Json)
    $self = Join-Path $Data 'LinuxifyPanel.ps1'; if (-not (Test-Path $self)) { $self = $PSCommandPath }
    Start-Process powershell -WindowStyle Hidden -ArgumentList "-NoProfile -STA -ExecutionPolicy Bypass -File `"$self`" -Tab geral"; $form.Close()
}
$lGl = New-Lbl (T 'Panel glass') $fUi; $lGl.Location = '22,552'; $pg.Controls.Add($lGl)
$tgGl = New-Object LxToggle; $tgGl.Location = '196,550'; $tgGl.On = $GlassOn; $pg.Controls.Add($tgGl)
$trGl = New-Object LxSlider; $trGl.Minimum = 20; $trGl.Maximum = 100; $trGl.SmallChange = 10; $trGl.SetBounds(260, 548, 240, 28); $trGl.Value = $GlassLvl; $trGl.Enabled = $GlassOn; $pg.Controls.Add($trGl)
$lGlV = New-Lbl "$GlassLvl%" $fS $cText; $lGlV.Location = '508,553'; $pg.Controls.Add($lGlV)
$trGl.add_ValueChanged({ $lGlV.Text = "$($trGl.Value)%" })
$tgGl.add_Flipped({ Restart-Panel 'Glass' $tgGl.On })
$trGl.add_MouseUp({ if ($trGl.Value -ne $GlassLvl) { Restart-Panel 'GlassLevel' $trGl.Value } })
$trGl.add_KeyUp({ if ($trGl.Value -ne $GlassLvl) { Restart-Panel 'GlassLevel' $trGl.Value } })
$cs = New-Card 20 446 560 138; $pg.Controls.Add($cs)
foreach ($x in @($cbBoot, $lLang, $cbLang, $cbDesk, $cbCorner, $lSz, $trSz, $lSzV, $lGl, $tgGl, $trGl, $lGlV)) { $pg.Controls.Remove($x); $x.Left -= 6; $x.Top -= 448; $cs.Controls.Add($x) }
function Update-Geral {
    $tgMode.On = (Test-Path (Join-Path $Data 'state.txt')) -and ((Get-Content (Join-Path $Data 'state.txt') -Raw).Trim() -eq 'on')
    foreach ($n in $Tools.Keys) {
        $r = $rows[$n]; $inst = Test-Installed $n; $on = Test-On $n
        $r.Tg.On = $on; $r.Tg.Enabled = $inst
        if (-not $inst) { $r.St.Text = (T 'Missing'); $r.St.ForeColor = $cOv; $r.St.BackColor = C '#34354a' }
        elseif ($on) { $r.St.Text = $(if ($n -eq 'Terminal') { T 'Applied' } else { T 'Running' }); $r.St.ForeColor = $cGreen; $r.St.BackColor = C '#2c3b37' }
        else { $r.St.Text = $(if ($n -eq 'Terminal') { T 'Original' } else { T 'Stopped' }); $r.St.ForeColor = $cYellow; $r.St.BackColor = C '#3d3a30' }
        if ($n -eq 'Terminal') { $r.Bt.Text = $(if ($inst) { T 'Remove theme' } else { T 'Install' }) } else { $r.Bt.Text = $(if ($inst) { T 'Uninstall' } else { T 'Install' }) }
        if ($inst) { $r.Bt.BackColor = C '#3a2a36'; $r.Bt.ForeColor = $cRed } else { $r.Bt.BackColor = $cMauve; $r.Bt.ForeColor = $cBase }
    }
    $cbBoot.Checked = [bool](Get-ItemProperty $Run -Name 'Linuxify' -ErrorAction SilentlyContinue)
}

# ===== Terminal =====
$pt = $pages['term']
$pref = @{ Scheme = 'Catppuccin Mocha'; Font = $monoName; Size = 11; Opacity = 85; Acrylic = $true; AsciiColor = '#cba6f7'; Banner = "  _     _`n | |   (_)_ __  _   ___  __`n | |   | | '_ \| | | \ \/ /`n | |___| | | | | |_| |>  <`n |_____|_|_| |_|\__,_/_/\_\" }
if (Test-Path $WtSet) { try { $d = (Read-Text $WtSet | ConvertFrom-Json).profiles.defaults; if ($d.colorScheme -and $Schemes[$d.colorScheme]) { $pref.Scheme = $d.colorScheme }; if ($d.font.face) { $pref.Font = $d.font.face }; if ($d.font.size) { $pref.Size = $d.font.size }; if ($d.opacity) { $pref.Opacity = $d.opacity }; if ($null -ne $d.useAcrylic) { $pref.Acrylic = $d.useAcrylic } } catch {} }
if (Test-Path $Prefs) { try { $sv = Read-Text $Prefs | ConvertFrom-Json; foreach ($k in 'AsciiColor', 'Banner') { if ($sv.$k) { $pref[$k] = $sv.$k } } } catch {} }
if (Test-Path $FfLogo) { try { $lg = Read-Text $FfLogo; if ($lg.Trim()) { $pref.Banner = $lg.TrimEnd() } } catch {} }
if ($Shot -and $env:LINUXIFY_DEMO -eq '1') { $dl = Join-Path $PSScriptRoot 'configs\fastfetch\logo-default.txt'; if (Test-Path $dl) { $pref.Banner = (Read-Text $dl).TrimEnd() } }
$l = New-Lbl (T 'ASCII BANNER') $fS $cSub; $l.Location = '20,16'; $pt.Controls.Add($l)
$tbB = New-Object System.Windows.Forms.TextBox; $tbB.Multiline = $true; $tbB.ScrollBars = 'Both'; $tbB.WordWrap = $false; $tbB.SetBounds(20, 36, 270, 170); $tbB.BackColor = $cMantle; $tbB.ForeColor = $cText; $tbB.BorderStyle = 'FixedSingle'; $tbB.Font = $fM; $tbB.Text = ($pref.Banner -replace "\r?\n", "`r`n"); $pt.Controls.Add($tbB)
$l = New-Lbl (T 'Paste your ASCII here - the rest is built for you') $fS $cOv; $l.Location = '20,210'; $pt.Controls.Add($l)
$l = New-Lbl (T 'PREVIEW') $fS $cSub; $l.Location = '310,16'; $pt.Controls.Add($l)
$rtP = New-Object System.Windows.Forms.RichTextBox; $rtP.SetBounds(310, 36, 270, 170); $rtP.ReadOnly = $true; $rtP.BorderStyle = 'None'; $rtP.Font = $fM; $rtP.WordWrap = $false; $rtP.ScrollBars = 'None'; $pt.Controls.Add($rtP)
$cc = New-Card 20 236 560 200; $pt.Controls.Add($cc)
$l = New-Lbl (T 'Color scheme') $fS $cSub; $l.Location = '14,12'; $cc.Controls.Add($l)
$cbS = New-Object LxCombo; $cbS.DropDownStyle = 'DropDownList'; $cbS.FlatStyle = 'Flat'; $cbS.BackColor = $cMantle; $cbS.ForeColor = $cText; $cbS.SetBounds(14, 32, 250, 24); [void]$cbS.Items.AddRange([object[]]@($Schemes.Keys | Sort-Object)); $cbS.SelectedItem = $pref.Scheme; $cc.Controls.Add($cbS)
$l = New-Lbl (T 'ASCII color') $fS $cSub; $l.Location = '290,12'; $cc.Controls.Add($l)
$sw = @(); $sx = 290
$tbC = New-Object System.Windows.Forms.TextBox; $tbC.BackColor = $cMantle; $tbC.ForeColor = $cText; $tbC.BorderStyle = 'FixedSingle'; $tbC.Font = $fM; $tbC.SetBounds(450, 33, 90, 22); $tbC.Text = $pref.AsciiColor
foreach ($hx in '#cba6f7', '#89b4fa', '#a6e3a1', '#fab387', '#f38ba8') { $s = New-Object System.Windows.Forms.Panel; $s.SetBounds($sx, 33, 22, 22); $s.BackColor = C $hx; $s.Tag = $hx; $s.Cursor = 'Hand'; $s.add_Click({ $tbC.Text = $this.Tag }); $cc.Controls.Add($s); $sx += 30 }
$cc.Controls.Add($tbC)
$l = New-Lbl (T 'Font') $fS $cSub; $l.Location = '14,70'; $cc.Controls.Add($l)
$cbF = New-Object LxCombo; $cbF.DropDownStyle = 'DropDownList'; $cbF.FlatStyle = 'Flat'; $cbF.BackColor = $cMantle; $cbF.ForeColor = $cText; $cbF.SetBounds(14, 90, 250, 24)
$fams = (New-Object System.Drawing.Text.InstalledFontCollection).Families | ForEach-Object Name | Where-Object { $_ -match 'Mono|Nerd|Code|Consolas|Courier|Cascadia|Hack|Fira|Iosevka' }
[void]$cbF.Items.AddRange([object[]]@($fams)); if (-not $cbF.Items.Contains($pref.Font)) { [void]$cbF.Items.Add($pref.Font) }; $cbF.SelectedItem = $pref.Font; $cc.Controls.Add($cbF)
$nuS = New-Object System.Windows.Forms.NumericUpDown; $nuS.Minimum = 6; $nuS.Maximum = 36; $nuS.Value = [int]$pref.Size; $nuS.SetBounds(272, 90, 56, 24); $nuS.BackColor = $cMantle; $nuS.ForeColor = $cText; $cc.Controls.Add($nuS)
$l = New-Lbl (T 'Transparency') $fUi; $l.Location = '14,136'; $cc.Controls.Add($l)
$trO = New-Object LxSlider; $trO.Minimum = 30; $trO.Maximum = 100; $trO.TickStyle = 'None'; $trO.SetBounds(120, 132, 380, 30); $trO.Value = [Math]::Min(100, [Math]::Max(30, [int]$pref.Opacity)); $trO.BackColor = $cS0; $cc.Controls.Add($trO)
$lO = New-Lbl "$($trO.Value)%" $fB; $lO.Location = '506,134'; $cc.Controls.Add($lO); $trO.add_ValueChanged({ $lO.Text = "$($trO.Value)%" })
$l = New-Lbl (T 'Acrylic effect') $fUi; $l.Location = '14,170'; $cc.Controls.Add($l)
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
$bRes = New-Btn (T 'Restore original') 'dg'; $bRes.Location = '20,590'; $pt.Controls.Add($bRes)
$bRes.add_Click({ if ([System.Windows.Forms.MessageBox]::Show((T 'Restore the original Windows Terminal settings.json (and the default fastfetch logo)?'), 'Linuxify', 'YesNo', 'Question') -eq 'Yes') { try { Restore-Terminal; [System.Windows.Forms.MessageBox]::Show((T 'Original restored.'), 'Linuxify') | Out-Null } catch { [System.Windows.Forms.MessageBox]::Show(((T 'Error: {0}') -f $_), 'Linuxify') | Out-Null } } })
$bAp = New-Btn (T 'Apply') 'pr'; $pt.Controls.Add($bAp); $bAp.Location = New-Object System.Drawing.Point((580 - $bAp.PreferredSize.Width), 590)
$bAp.add_Click({
    try { $b = Apply-Terminal ([pscustomobject]@{ Scheme = [string]$cbS.SelectedItem; Font = [string]$cbF.SelectedItem; Size = [int]$nuS.Value; Opacity = $trO.Value; Acrylic = $tgA.On; AsciiColor = $tbC.Text; Banner = $tbB.Text })
          [System.Windows.Forms.MessageBox]::Show(((T 'Applied. Backup: {0}') -f $b), 'Linuxify') | Out-Null } catch { [System.Windows.Forms.MessageBox]::Show(((T 'Error: {0}') -f $_), 'Linuxify') | Out-Null }
})

# ===== Excecoes =====
$pe = $pages['exc']
$l = New-Lbl (T 'GlazeWM exceptions') $fH; $l.Location = '18,12'; $pe.Controls.Add($l)
$l = New-Lbl (T 'Apps listed here are not tiled by GlazeWM. "Games (scan)" = games rule.') $fS $cOv; $l.Location = '20,44'; $pe.Controls.Add($l)
$tbQ = New-Object System.Windows.Forms.TextBox; $tbQ.SetBounds(20, 70, 440, 26); $tbQ.BackColor = $cMantle; $tbQ.ForeColor = $cText; $tbQ.BorderStyle = 'FixedSingle'; $pe.Controls.Add($tbQ)
$lv = New-Object System.Windows.Forms.ListView; $lv.View = 'Details'; $lv.FullRowSelect = $true; $lv.HeaderStyle = 'None'; $lv.BorderStyle = 'None'; $lv.SetBounds(20, 106, 560, 466); $lv.BackColor = $cS0; $lv.ForeColor = $cText; $lv.Font = $fM
[void]$lv.Columns.Add((T 'Process'), 360); [void]$lv.Columns.Add((T 'Source'), 180); $pe.Controls.Add($lv)
$script:exc = @()
function Load-Exc { $script:exc = @(Get-Exclusions); Fill-Exc }
function Fill-Exc {
    $lv.BeginUpdate(); $lv.Items.Clear()
    foreach ($e in $script:exc) { if ($tbQ.Text -and $e.Name -notlike "*$($tbQ.Text)*") { continue }; $it = New-Object System.Windows.Forms.ListViewItem("$($e.Name).exe"); [void]$it.SubItems.Add((T $e.Src)); $it.Tag = $e; if ($e.Src -ne 'Painel') { $it.ForeColor = $cSub }; [void]$lv.Items.Add($it) }
    $lv.EndUpdate()
}
$tbQ.add_TextChanged({ Fill-Exc })
function Save-Exc([string[]]$names) {
    try { $b = Save-PanelExclusions $names; Load-Exc; return $b } catch { [System.Windows.Forms.MessageBox]::Show(((T 'Error: {0}') -f $_), 'Linuxify') | Out-Null }
}
function Add-Exc([string]$name) {
    $name = ($name.Trim() -replace '\.exe$', ''); if (-not $name) { return }
    if ($script:exc | Where-Object { $_.Name -ieq $name }) { return }
    Save-Exc (@($script:exc | Where-Object Src -eq 'Painel' | ForEach-Object Name) + $name) | Out-Null
}
$bAdd = New-Btn (T '+ Add') 'pr'; $bAdd.AutoSize = $false; $bAdd.SetBounds(20, 590, 180, 32); $pe.Controls.Add($bAdd)
$bAdd.add_Click({ if ($tbQ.Text.Trim()) { Add-Exc $tbQ.Text; $tbQ.Text = '' } else { [System.Windows.Forms.MessageBox]::Show((T 'Type the process name (e.g. game.exe) in the search box and click again.'), 'Linuxify') | Out-Null } })
$bPick = New-Btn (T '+ Open window'); $bPick.AutoSize = $false; $bPick.SetBounds(208, 590, 190, 32); $pe.Controls.Add($bPick)
$bPick.add_Click({
    $cm2 = New-Object System.Windows.Forms.ContextMenuStrip
    Get-Process | Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle } | Sort-Object ProcessName -Unique | ForEach-Object { $mi = $cm2.Items.Add("$($_.ProcessName)  -  $($_.MainWindowTitle)"); $mi.Tag = $_.ProcessName; $mi.add_Click({ Add-Exc $this.Tag }) }
    $cm2.Show($bPick, 0, $bPick.Height)
})
$bDel = New-Btn (T 'Remove'); $bDel.AutoSize = $false; $bDel.SetBounds(406, 590, 174, 32); $pe.Controls.Add($bDel)
$bDel.add_Click({
    $sel = @($lv.SelectedItems | ForEach-Object { $_.Tag })
    if ($sel | Where-Object Src -ne 'Painel') { [System.Windows.Forms.MessageBox]::Show((T '"Games (scan)" items belong to the games rule; edit them via the scan.'), 'Linuxify') | Out-Null }
    $rm = @($sel | Where-Object Src -eq 'Painel' | ForEach-Object Name); if (-not $rm) { return }
    Save-Exc @($script:exc | Where-Object { $_.Src -eq 'Painel' -and $rm -notcontains $_.Name } | ForEach-Object Name) | Out-Null
})
$bRel = New-Btn (T 'Reload'); $bRel.AutoSize = $false; $bRel.SetBounds(470, 68, 110, 28); $pe.Controls.Add($bRel); $bRel.add_Click({ Load-Exc })

# ===== Transparencia =====
$pa = $pages['transp']; $script:tcfg = Get-LxTransp
$l = New-Lbl (T 'Window transparency') $fH; $l.Location = '18,12'; $pa.Controls.Add($l)
$l = New-Lbl (T 'Pick a window and adjust its opacity (live). Save it as a rule for the app.') $fS $cOv; $l.Location = '20,44'; $pa.Controls.Add($l)
$lvT = New-Object System.Windows.Forms.ListView; $lvT.View = 'Details'; $lvT.FullRowSelect = $true; $lvT.MultiSelect = $false; $lvT.HideSelection = $false; $lvT.HeaderStyle = 'Nonclickable'; $lvT.BorderStyle = 'None'; $lvT.SetBounds(20, 70, 560, 250); $lvT.BackColor = $cS0; $lvT.ForeColor = $cText; $lvT.Font = $fUi
[void]$lvT.Columns.Add((T 'Window'), 330); [void]$lvT.Columns.Add((T 'Process'), 140); [void]$lvT.Columns.Add((T 'Opac.'), 70); $pa.Controls.Add($lvT)
foreach ($lvx in @($lvT)) { $lvx.OwnerDraw = $true; $lvx.HeaderStyle = 'Nonclickable'
    $lvx.add_DrawColumnHeader({ param($s, $e) $e.Graphics.FillRectangle((New-Object System.Drawing.SolidBrush($cS0)), $e.Bounds); [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, $e.Header.Text, $fS, (New-Object System.Drawing.Rectangle(($e.Bounds.X + 6), $e.Bounds.Y, ($e.Bounds.Width - 8), $e.Bounds.Height)), $cSub, [System.Windows.Forms.TextFormatFlags]'VerticalCenter, EndEllipsis, SingleLine') })
    $lvx.add_DrawItem({ param($s, $e) $e.DrawDefault = $true }); $lvx.add_DrawSubItem({ param($s, $e) $e.DrawDefault = $true }) }
function Fill-Transp {
    $lvT.BeginUpdate(); $lvT.Items.Clear()
    foreach ($w in [LxAlpha]::List()) {
        $a = [LxAlpha]::Get($w.Handle); $pc = if ($a -lt 0) { '100%' } else { "$([int][Math]::Round($a * 100 / 255))%" }
        $it = New-Object System.Windows.Forms.ListViewItem($w.Title); [void]$it.SubItems.Add($w.Proc); [void]$it.SubItems.Add($pc); $it.Tag = $w
        if ($pc -ne '100%') { $it.ForeColor = $cMauve }; [void]$lvT.Items.Add($it)
    }
    $lvT.EndUpdate()
}
$ca = New-Card 20 330 560 206; $pa.Controls.Add($ca)
$lSel = New-Lbl (T 'No window selected') $fB; $lSel.AutoSize = $false; $lSel.SetBounds(14, 10, 530, 22); $ca.Controls.Add($lSel)
$l = New-Lbl (T 'Opacity') $fUi; $l.Location = '14,46'; $ca.Controls.Add($l)
$trT = New-Object LxSlider; $trT.Minimum = 20; $trT.Maximum = 100; $trT.Value = 100; $trT.TickStyle = 'None'; $trT.AutoSize = $false; $trT.SetBounds(100, 42, 390, 40); $trT.BackColor = $cS0; $ca.Controls.Add($trT)
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
$bRule = New-Btn (T 'Save app rule'); $bRule.AutoSize = $false; $bRule.SetBounds(14, 100, 190, 40); $ca.Controls.Add($bRule)
$bRule.add_Click({
    if (-not $script:tSel) { return }; $p = $script:tSel.Proc
    $script:tcfg.Rules = @($script:tcfg.Rules | Where-Object { $_.Process -ine $p }) + [pscustomobject]@{ Process = $p; Opacity = $trT.Value }
    Save-LxTransp $script:tcfg; Fill-Rules
})
$bOne = New-Btn (T 'Restore'); $bOne.AutoSize = $false; $bOne.SetBounds(214, 100, 140, 40); $ca.Controls.Add($bOne)
$bOne.add_Click({ if ($script:tSel) { [LxAlpha]::Restore($script:tSel.Handle); $script:tMute = $true; $trT.Value = 100; $script:tMute = $false; $lT.Text = '100%'; Fill-Transp } })
$l = New-Lbl (T 'Saved rules (per app):') $fS $cOv; $l.Location = '14,170'; $ca.Controls.Add($l)
$cbR = New-Object LxCombo; $cbR.DropDownStyle = 'DropDownList'; $cbR.FlatStyle = 'Flat'; $cbR.SetBounds(170, 166, 170, 24); $ca.Controls.Add($cbR)
$bREd = New-Btn (T 'Use current %'); $bREd.AutoSize = $false; $bREd.SetBounds(348, 163, 106, 30); $ca.Controls.Add($bREd)
$bRDel = New-Btn (T 'Remove') 'dg'; $bRDel.AutoSize = $false; $bRDel.SetBounds(460, 163, 88, 30); $ca.Controls.Add($bRDel)
function Fill-Rules {
    $cbR.Items.Clear(); foreach ($r in @($script:tcfg.Rules)) { [void]$cbR.Items.Add("$($r.Process)  $($r.Opacity)%") }
    if ($cbR.Items.Count) { $cbR.SelectedIndex = 0; $cbR.Enabled = $true } else { [void]$cbR.Items.Add((T '(none)')); $cbR.SelectedIndex = 0; $cbR.Enabled = $false }
    $bREd.Enabled = $cbR.Enabled; $bRDel.Enabled = $cbR.Enabled
}
function Get-SelRule { if (-not $cbR.Enabled -or $cbR.SelectedIndex -lt 0) { return $null }; @($script:tcfg.Rules)[$cbR.SelectedIndex] }
$cbR.add_SelectedIndexChanged({ $r = Get-SelRule; if ($r) { $script:tMute = $true; $trT.Value = [Math]::Max(20, [Math]::Min(100, [int]$r.Opacity)); $script:tMute = $false; $lT.Text = "$($trT.Value)%" } })
$bREd.add_Click({ $r = Get-SelRule; if (-not $r) { return }; $r.Opacity = $trT.Value; Save-LxTransp $script:tcfg; Fill-Rules; foreach ($w in [LxAlpha]::List()) { if ($w.Proc -ieq $r.Process) { if ($r.Opacity -ge 100) { [LxAlpha]::Restore($w.Handle) } else { [void][LxAlpha]::Set($w.Handle, [int]$r.Opacity) } } }; Fill-Transp })
$bRDel.add_Click({ $r = Get-SelRule; if (-not $r) { return }; $script:tcfg.Rules = @($script:tcfg.Rules | Where-Object { $_.Process -ine $r.Process }); Save-LxTransp $script:tcfg; foreach ($w in [LxAlpha]::List()) { if ($w.Proc -ieq $r.Process -and [LxAlpha]::Get($w.Handle) -ge 0) { [LxAlpha]::Restore($w.Handle) } }; Fill-Rules; Fill-Transp })
$cbTS = New-Object System.Windows.Forms.CheckBox; $cbTS.Text = (T 'Apply rules automatically (new and reopened windows)'); $cbTS.AutoSize = $true; $cbTS.Location = '22,548'; $cbTS.ForeColor = $cText; $cbTS.Checked = $script:tcfg.ApplyOnStart; $pa.Controls.Add($cbTS)
$cbTS.add_CheckedChanged({ $script:tcfg.ApplyOnStart = $cbTS.Checked; Save-LxTransp $script:tcfg })
$bAct = New-Btn (T '+ Active window'); $bAct.AutoSize = $false; $bAct.SetBounds(20, 584, 190, 40); $pa.Controls.Add($bAct)
$bAct.add_Click({
    $bAct.Text = ((T 'Click the window... {0}') -f 3); $form.Refresh()
    foreach ($n in 2, 1, 0) { for ($i = 0; $i -lt 10; $i++) { Start-Sleep -Milliseconds 100; [System.Windows.Forms.Application]::DoEvents() }; $bAct.Text = ((T 'Click the window... {0}') -f $n); $form.Refresh() }
    $h = [LxAlpha]::GetForegroundWindow(); $bAct.Text = (T '+ Active window')
    Fill-Transp; foreach ($it in $lvT.Items) { if ($it.Tag.Handle -eq $h) { $it.Selected = $true; $it.EnsureVisible() } }
    $form.Activate()
})
$bTRel = New-Btn (T 'Reload'); $bTRel.AutoSize = $false; $bTRel.SetBounds(218, 584, 140, 40); $pa.Controls.Add($bTRel); $bTRel.add_Click({ Fill-Transp })
$bAll = New-Btn (T 'Restore all') 'dg'; $bAll.AutoSize = $false; $bAll.SetBounds(400, 584, 180, 40); $pa.Controls.Add($bAll)
$bAll.add_Click({
    foreach ($w in [LxAlpha]::List()) { if ([LxAlpha]::Get($w.Handle) -ge 0) { [LxAlpha]::Restore($w.Handle) } }
    $script:tcfg.Rules = @(); Save-LxTransp $script:tcfg; Fill-Rules; Fill-Transp; $script:tMute = $true; $trT.Value = 100; $script:tMute = $false; $lT.Text = '100%'
})
Fill-Rules

Update-Preview
Show-Tab $(if ($Tab) { $Tab } else { 'geral' })
if ($Shot) {
    Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class LxShot { [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr h, int a, int[] r, int s); public static int Get(IntPtr h, int[] r) { return DwmGetWindowAttribute(h, 9, r, 16); } }' -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force $Shot | Out-Null
    $form.TopMost = $true
    $form.add_Shown({
        foreach ($k in 'geral', 'term', 'exc', 'transp') {
            Show-Tab $k; $form.Activate(); $form.Refresh(); [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 600; [System.Windows.Forms.Application]::DoEvents()
            $r = $form.Bounds; try { $rb = New-Object int[] 4; [void][LxShot]::Get($form.Handle, $rb); $r = New-Object System.Drawing.Rectangle($rb[0], $rb[1], ($rb[2] - $rb[0]), ($rb[3] - $rb[1])) } catch {}; $bmp = New-Object System.Drawing.Bitmap $r.Width, $r.Height
            $gs = [System.Drawing.Graphics]::FromImage($bmp); try { $gs.CopyFromScreen($r.Location, [System.Drawing.Point]::Empty, $r.Size) } catch { $form.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle 0, 0, $r.Width, $r.Height)) }; $gs.Dispose()
            $bmp.Save((Join-Path $Shot "panel-$k.png"), [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
        }
        $form.Close()
    })
}
function Set-LxStyle($c) {
    foreach ($x in $c.Controls) {
        if ($x -is [System.Windows.Forms.CheckBox]) { $x.FlatStyle = 'Flat'; $x.FlatAppearance.BorderColor = $cS2; $x.FlatAppearance.CheckedBackColor = $cMauve; $x.Cursor = 'Hand'; $x.BackColor = [System.Drawing.Color]::Transparent }
        elseif ($x -is [System.Windows.Forms.ListView]) { $x.BackColor = $cCard }
        elseif ($x -is [LxCombo]) { $x.BackColor = $cMantle; $x.ForeColor = $cText; $x.HiBack = $cS1 }
        if ($x.Controls.Count) { Set-LxStyle $x }
    }
}
Set-LxStyle $form
$scr = if ($Shot) { [System.Windows.Forms.Screen]::PrimaryScreen } else { [System.Windows.Forms.Screen]::FromPoint([System.Windows.Forms.Cursor]::Position) }
$sf = 0; try { $mc = $scr.Bounds.Location; $mc.Offset(10, 10); $hm = [Lx.Dpi]::MonitorFromPoint($mc, 2); [uint32]$dx = 0; [uint32]$dy = 0; if ([Lx.Dpi]::GetDpiForMonitor($hm, 0, [ref]$dx, [ref]$dy) -eq 0) { $sf = $dx / 96.0 } } catch {}
if ($sf -le 0) { $gx = $form.CreateGraphics(); $sf = $gx.DpiX / 96.0; $gx.Dispose() }
# fonts are created at system DPI; on another monitor rescale them by the ratio
$gx = $form.CreateGraphics(); $sysF = $gx.DpiX / 96.0; $gx.Dispose()
if ([Math]::Abs($sf - 1) -gt 0.01) { $form.Scale((New-Object System.Drawing.SizeF([single]$sf, [single]$sf))) }
$form.ClientSize = New-Object System.Drawing.Size([int](780 * $sf), [int](640 * $sf))
foreach ($lvx in @($lv, $lvT)) { $n0 = $lvx.Columns.Count; for ($ci = 0; $ci -lt $n0 - 1; $ci++) { $lvx.Columns[$ci].Width = [int]($lvx.Columns[$ci].Width * $sf) }; $used = 0; for ($ci = 0; $ci -lt $n0 - 1; $ci++) { $used += $lvx.Columns[$ci].Width }; $lvx.Columns[$n0 - 1].Width = [Math]::Max(40, $lvx.ClientSize.Width - $used - [System.Windows.Forms.SystemInformation]::VerticalScrollBarWidth) }
if ([Math]::Abs($sf - $sysF) -gt 0.01) { $fr = $sf / $sysF; $fl = New-Object System.Collections.ArrayList; function Get-Fonts($c) { foreach ($x in $c.Controls) { [void]$fl.Add(@($x, $x.Font)); if ($x.Controls.Count) { Get-Fonts $x } } }; Get-Fonts $form; foreach ($e in $fl) { $e[0].Font = New-Object System.Drawing.Font($e[1].FontFamily, [single]($e[1].Size * $fr), $e[1].Style); if ($e[0] -is [LxNav] -and $e[0].GlyphFont) { $e[0].GlyphFont = New-Object System.Drawing.Font($e[0].GlyphFont.FontFamily, [single]($e[0].GlyphFont.Size * $fr)) } } }
$form.StartPosition = 'Manual'; $wa = $scr.WorkingArea; $form.Location = New-Object System.Drawing.Point(($wa.X + [int](($wa.Width - $form.Width) / 2)), ($wa.Y + [int][Math]::Max(0, ($wa.Height - $form.Height) / 2)))
[void]$form.ShowDialog()
