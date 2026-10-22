<#
.SYNOPSIS Linuxify desktop widget: fastfetch output pinned to the desktop (bottom of z-order).
  Settings in %LOCALAPPDATA%\Linuxify\desktop.json: Enabled, Corner (TopLeft|TopRight|BottomLeft|BottomRight), Opacity (20-100), Refresh (s).
#>
$Data = Join-Path $env:LOCALAPPDATA 'Linuxify'
$Cfg  = Join-Path $Data 'desktop.json'
$mutex = New-Object System.Threading.Mutex($false, 'Local\LinuxifyDesktop')
if (-not $mutex.WaitOne(0)) { return }
function Get-DeskCfg {
    $d = [pscustomobject]@{ Enabled = $true; Corner = 'BottomRight'; Opacity = 85; Refresh = 45 }
    if (Test-Path $Cfg) { try { $j = Get-Content $Cfg -Raw | ConvertFrom-Json; foreach ($p in $j.PSObject.Properties) { $d | Add-Member $p.Name $p.Value -Force } } catch {} }
    $d
}
function Save-DeskCfg($c) { [IO.File]::WriteAllText($Cfg, ($c | ConvertTo-Json), (New-Object System.Text.UTF8Encoding($false))) }
$cfg = Get-DeskCfg

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
using System; using System.Runtime.InteropServices; using System.Windows.Forms;
public class LxDeskForm : Form {
  [StructLayout(LayoutKind.Sequential)] struct WINDOWPOS { public IntPtr hwnd, after; public int x, y, cx, cy; public uint flags; }
  [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
  protected override CreateParams CreateParams { get { CreateParams p = base.CreateParams; p.ExStyle |= 0x80 | 0x08000000; return p; } }
  protected override bool ShowWithoutActivation { get { return true; } }
  public void ToBottom() { SetWindowPos(Handle, new IntPtr(1), 0, 0, 0, 0, 0x13); }
  protected override void WndProc(ref Message m) {
    if (m.Msg == 0x46) { WINDOWPOS wp = (WINDOWPOS)Marshal.PtrToStructure(m.LParam, typeof(WINDOWPOS)); wp.after = new IntPtr(1); wp.flags &= ~0x4u; Marshal.StructureToPtr(wp, m.LParam, false); }
    base.WndProc(ref m);
  }
}
'@

# Basic ANSI palette (Catppuccin Mocha)
$Pal = @('#45475A','#F38BA8','#A6E3A1','#F9E2AF','#89B4FA','#F5C2E7','#94E2D5','#BAC2DE','#585B70','#F38BA8','#A6E3A1','#F9E2AF','#89B4FA','#F5C2E7','#94E2D5','#A6ADC8') | ForEach-Object { [System.Drawing.ColorTranslator]::FromHtml($_) }
$Fg0 = [System.Drawing.ColorTranslator]::FromHtml('#CDD6F4')
$Bg0 = [System.Drawing.ColorTranslator]::FromHtml('#1E1E2E')

function Get-Fetch {
    $ff = Get-Command fastfetch -ErrorAction SilentlyContinue
    if (-not $ff) { return "fastfetch not found`n(install it from the Linuxify panel)" }
    $psi = New-Object System.Diagnostics.ProcessStartInfo $ff.Source
    $psi.Arguments = '--pipe false --structure Title:Separator:OS:Kernel:Uptime:Packages:Shell:Display:WM:CPU:GPU:Memory:Break:Colors'
    $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.EnvironmentVariables['COLUMNS'] = '120'
    $p = [System.Diagnostics.Process]::Start($psi); $o = $p.StandardOutput.ReadToEnd(); $p.WaitForExit(15000) | Out-Null; $o
}

# Tiny terminal emulator: builds a grid of (char, fg, bg) handling SGR + cursor moves
function Convert-Ansi([string]$s) {
    $rows = New-Object System.Collections.ArrayList
    $r = 0; $c = 0; $fg = $Fg0; $bg = $null; $bold = $false
    $i = 0
    while ($i -lt $s.Length) {
        $ch = $s[$i]
        if ($ch -eq [char]27 -and $i + 1 -lt $s.Length -and $s[$i + 1] -eq '[') {
            $j = $i + 2; while ($j -lt $s.Length -and -not [char]::IsLetter($s[$j])) { $j++ }
            if ($j -ge $s.Length) { break }
            $prm = $s.Substring($i + 2, $j - $i - 2).TrimStart('?'); $cmd = $s[$j]; $i = $j + 1
            $n = 1; if ($prm -match '^\d+$') { $n = [int]$prm }
            switch -CaseSensitive ($cmd) {
                'A' { $r = [Math]::Max(0, $r - $n) } 'B' { $r += $n } 'C' { $c += $n } 'D' { $c = [Math]::Max(0, $c - $n) }
                'G' { $c = [Math]::Max(0, $n - 1) }
                'm' {
                    $a = @($prm -split ';' | ForEach-Object { if ($_ -eq '') { 0 } else { [int]$_ } }); if ($a.Count -eq 0) { $a = @(0) }
                    for ($k = 0; $k -lt $a.Count; $k++) {
                        $v = $a[$k]
                        if ($v -eq 0) { $fg = $Fg0; $bg = $null; $bold = $false }
                        elseif ($v -eq 1) { $bold = $true }
                        elseif ($v -ge 30 -and $v -le 37) { $fg = $Pal[$v - 30 + $(if ($bold) { 8 } else { 0 })] }
                        elseif ($v -ge 90 -and $v -le 97) { $fg = $Pal[$v - 82] }
                        elseif ($v -ge 40 -and $v -le 47) { $bg = $Pal[$v - 40] }
                        elseif ($v -ge 100 -and $v -le 107) { $bg = $Pal[$v - 92] }
                        elseif ($v -eq 39) { $fg = $Fg0 } elseif ($v -eq 49) { $bg = $null }
                        elseif (($v -eq 38 -or $v -eq 48) -and $k + 1 -lt $a.Count) {
                            $col = $null
                            if ($a[$k + 1] -eq 2 -and $k + 4 -lt $a.Count) { $col = [System.Drawing.Color]::FromArgb($a[$k + 2], $a[$k + 3], $a[$k + 4]); $k += 4 }
                            elseif ($a[$k + 1] -eq 5 -and $k + 2 -lt $a.Count) { $x = $a[$k + 2]; if ($x -lt 16) { $col = $Pal[$x] } else { $col = $Fg0 }; $k += 2 }
                            if ($col) { if ($v -eq 38) { $fg = $col } else { $bg = $col } }
                        }
                    }
                }
            }
            continue
        }
        $i++
        $txt = [string]$ch
        if ([char]::IsHighSurrogate($ch) -and $i -lt $s.Length) { $txt += $s[$i]; $i++ }
        if ($ch -eq "`r") { $c = 0; continue }
        if ($ch -eq "`n") { $r++; $c = 0; continue }
        while ($rows.Count -le $r) { [void]$rows.Add((New-Object System.Collections.ArrayList)) }
        $line = $rows[$r]
        while ($line.Count -le $c) { [void]$line.Add(@(' ', $Fg0, $null)) }
        $line[$c] = @($txt, $fg, $bg); $c++
    }
    while ($rows.Count -gt 0 -and ($rows[$rows.Count - 1] | Where-Object { $_[0] -ne ' ' -or $_[2] }).Count -eq 0) { $rows.RemoveAt($rows.Count - 1) }
    ,$rows
}

$font = $null
foreach ($f in 'JetBrainsMono Nerd Font Mono', 'JetBrainsMono Nerd Font', 'Cascadia Mono', 'Consolas') {
    $t = New-Object System.Drawing.Font($f, 9); if ($t.Name -eq $f) { $font = $t; break }
}
$form = New-Object LxDeskForm
$form.Text = 'Linuxify Desktop'; $form.FormBorderStyle = 'None'; $form.ShowInTaskbar = $false; $form.TopMost = $false
$form.StartPosition = 'Manual'; $form.BackColor = $Bg0; $form.Padding = New-Object System.Windows.Forms.Padding(14, 12, 14, 12)
$form.Opacity = [Math]::Max(0.2, [Math]::Min(1.0, [double]$cfg.Opacity / 100))
$rt = New-Object System.Windows.Forms.RichTextBox
$rt.Dock = 'Fill'; $rt.ReadOnly = $true; $rt.BorderStyle = 'None'; $rt.BackColor = $Bg0; $rt.ForeColor = $Fg0
$rt.Font = $font; $rt.ScrollBars = 'None'; $rt.WordWrap = $false; $rt.Cursor = 'Arrow'; $rt.TabStop = $false
$form.Controls.Add($rt)
$x = New-Object System.Windows.Forms.Label
$x.Text = 'x'; $x.AutoSize = $false; $x.Size = '18,18'; $x.TextAlign = 'MiddleCenter'; $x.ForeColor = $Pal[8]; $x.BackColor = $Bg0
$x.Font = New-Object System.Drawing.Font('Segoe UI', 9); $x.Cursor = 'Hand'
$form.Controls.Add($x); $x.BringToFront()
$x.add_MouseEnter({ $x.ForeColor = $Pal[1] }); $x.add_MouseLeave({ $x.ForeColor = $Pal[8] })
$x.add_Click({ $c = Get-DeskCfg; $c.Enabled = $false; Save-DeskCfg $c; $form.Close() })
$rt.add_GotFocus({ $form.ToBottom() })

function Update-Widget {
    $grid = Convert-Ansi (Get-Fetch)
    $rt.Clear(); $w = 0
    for ($r = 0; $r -lt $grid.Count; $r++) {
        $line = $grid[$r]; if ($line.Count -gt $w) { $w = $line.Count }
        foreach ($cell in $line) {
            $rt.SelectionStart = $rt.TextLength; $rt.SelectionColor = $cell[1]
            $rt.SelectionBackColor = $(if ($cell[2]) { $cell[2] } else { $Bg0 })
            $rt.AppendText($cell[0])
        }
        if ($r -lt $grid.Count - 1) { $rt.AppendText("`n") }
    }
    $sz = [System.Windows.Forms.TextRenderer]::MeasureText(('W' * [Math]::Max(10, $w)), $font)
    $cw = $sz.Width; $lh = $font.GetHeight() + 1
    $form.ClientSize = New-Object System.Drawing.Size(([int]$cw + 34), ([int]($lh * [Math]::Max(3, $grid.Count)) + 30))
    $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea; $m = 24
    $c = (Get-DeskCfg).Corner
    $px = if ($c -like '*Left') { $wa.Left + $m } else { $wa.Right - $form.Width - $m }
    $py = if ($c -like 'Top*') { $wa.Top + $m + 40 } else { $wa.Bottom - $form.Height - $m }
    $form.Location = New-Object System.Drawing.Point($px, $py)
    $x.Location = New-Object System.Drawing.Point(($form.ClientSize.Width - 22), 4)
    $form.ToBottom()
}
$form.add_Shown({ Update-Widget })
$tm = New-Object System.Windows.Forms.Timer; $tm.Interval = [Math]::Max(15, [int]$cfg.Refresh) * 1000
$tm.add_Tick({ if (-not (Get-DeskCfg).Enabled) { $form.Close(); return }; Update-Widget }); $tm.Start()
[System.Windows.Forms.Application]::Run($form)
$mutex.ReleaseMutex()
