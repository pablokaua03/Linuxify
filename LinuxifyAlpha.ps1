# Linuxify - helpers compartilhados (logo + transparencia de janelas). ASCII-only.
$LxTranspFile = Join-Path (Join-Path $env:LOCALAPPDATA 'Linuxify') 'transparency.json'
if (-not ('LxAlpha' -as [type])) {
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System; using System.Collections.Generic; using System.Text; using System.Runtime.InteropServices;
using System.Drawing; using System.Drawing.Drawing2D;
public class LxWin { public IntPtr Handle; public string Title; public string Proc; public int Pid; }
public static class LxAlpha {
  delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out int pid);
  [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr h, uint cmd);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll", EntryPoint="GetWindowLongPtrW")] static extern IntPtr GetWLP(IntPtr h, int i);
  [DllImport("user32.dll", EntryPoint="SetWindowLongPtrW")] static extern IntPtr SetWLP(IntPtr h, int i, IntPtr v);
  [DllImport("user32.dll")] static extern bool SetLayeredWindowAttributes(IntPtr h, uint key, byte a, uint f);
  [DllImport("user32.dll")] static extern bool GetLayeredWindowAttributes(IntPtr h, out uint key, out byte a, out uint f);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern bool SetProp(IntPtr h, string n, IntPtr d);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern IntPtr GetProp(IntPtr h, string n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern IntPtr RemoveProp(IntPtr h, string n);
  [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr h, int a, out int v, int s);
  const int GWL_EXSTYLE = -20; const long WS_EX_LAYERED = 0x80000, WS_EX_TOOLWINDOW = 0x80; const uint LWA_ALPHA = 2;
  const string PROP = "LinuxifyAddedLayered";
  public static List<LxWin> List() {
    var r = new List<LxWin>(); int me = System.Diagnostics.Process.GetCurrentProcess().Id;
    EnumWindows((h, l) => {
      if (!IsWindowVisible(h) || GetWindow(h, 4) != IntPtr.Zero) return true;
      long ex = GetWLP(h, GWL_EXSTYLE).ToInt64(); if ((ex & WS_EX_TOOLWINDOW) != 0) return true;
      int cl; if (DwmGetWindowAttribute(h, 14, out cl, 4) == 0 && cl != 0) return true;
      var sb = new StringBuilder(512); GetWindowText(h, sb, 512); if (sb.Length == 0) return true;
      int pid; GetWindowThreadProcessId(h, out pid); if (pid == me) return true;
      string pn = "?"; try { pn = System.Diagnostics.Process.GetProcessById(pid).ProcessName; } catch {}
      r.Add(new LxWin { Handle = h, Title = sb.ToString(), Proc = pn, Pid = pid }); return true; }, IntPtr.Zero);
    return r;
  }
  public static bool Set(IntPtr h, int pct) {
    if (pct < 20) pct = 20; if (pct > 100) pct = 100;
    long ex = GetWLP(h, GWL_EXSTYLE).ToInt64();
    if ((ex & WS_EX_LAYERED) == 0) { SetWLP(h, GWL_EXSTYLE, new IntPtr(ex | WS_EX_LAYERED)); SetProp(h, PROP, new IntPtr(1)); }
    SetProp(h, "LinuxifyPct", new IntPtr(pct));
    return SetLayeredWindowAttributes(h, 0, (byte)Math.Round(pct * 255.0 / 100), LWA_ALPHA);
  }
  public static int Get(IntPtr h) {
    if ((GetWLP(h, GWL_EXSTYLE).ToInt64() & WS_EX_LAYERED) == 0) return -1;
    uint k, f; byte a; if (!GetLayeredWindowAttributes(h, out k, out a, out f) || (f & LWA_ALPHA) == 0) return -1; return a;
  }
  public static int Manual(IntPtr h) { return GetProp(h, "LinuxifyPct").ToInt32(); }
  public static bool Ours(IntPtr h) { return GetProp(h, PROP) != IntPtr.Zero; }
  public static void Restore(IntPtr h) {
    if (!IsWindow(h)) return; RemoveProp(h, "LinuxifyPct");
    long ex = GetWLP(h, GWL_EXSTYLE).ToInt64(); if ((ex & WS_EX_LAYERED) == 0) return;
    SetLayeredWindowAttributes(h, 0, 255, LWA_ALPHA);
    if (Ours(h)) { SetWLP(h, GWL_EXSTYLE, new IntPtr(ex & ~WS_EX_LAYERED)); RemoveProp(h, PROP); }
  }
  // Logo: circulo + chevron desenhado (centralizado), antialias.
  public static Bitmap Logo(int s, Color c) {
    var b = new Bitmap(s, s); using (var g = Graphics.FromImage(b)) {
      g.SmoothingMode = SmoothingMode.AntiAlias; g.PixelOffsetMode = PixelOffsetMode.HighQuality; g.Clear(Color.Transparent);
      using (var br = new SolidBrush(c)) g.FillEllipse(br, 0.5f, 0.5f, s - 1f, s - 1f);
      float w = Math.Max(1.6f, s * 0.13f);
      using (var p = new Pen(Color.FromArgb(17,17,27), w)) { p.StartCap = LineCap.Round; p.EndCap = LineCap.Round; p.LineJoin = LineJoin.Round;
        float cx = s / 2f, cy = s / 2f, hw = s * 0.12f, hh = s * 0.21f;
        g.DrawLines(p, new PointF[] { new PointF(cx - hw, cy - hh), new PointF(cx + hw, cy), new PointF(cx - hw, cy + hh) }); }
    } return b;
  }
}
'@
}
function Get-LxTransp {
    $d = [pscustomobject]@{ ApplyOnStart = $false; Rules = @() }
    if (Test-Path $LxTranspFile) { try { $j = [IO.File]::ReadAllText($LxTranspFile) | ConvertFrom-Json; if ($j) { $d.ApplyOnStart = [bool]$j.ApplyOnStart; $d.Rules = @($j.Rules | Where-Object { $_.Process }) } } catch {} }
    $d
}
function Save-LxTransp($cfg) {
    $o = [ordered]@{ ApplyOnStart = [bool]$cfg.ApplyOnStart; Rules = @($cfg.Rules | ForEach-Object { [ordered]@{ Process = [string]$_.Process; Opacity = [int]$_.Opacity } }) }
    [IO.File]::WriteAllText($LxTranspFile, (ConvertTo-Json $o -Depth 4), (New-Object System.Text.UTF8Encoding($false)))
}
# Aplica regras a janelas que ainda nao estao com a opacidade da regra.
function Invoke-LxTranspRules($cfg) {
    if (-not $cfg.Rules) { return }
    foreach ($w in [LxAlpha]::List()) {
        $r = $cfg.Rules | Where-Object { $_.Process -ieq $w.Proc } | Select-Object -First 1
        if ($r) { $want = [int][Math]::Round([int]$r.Opacity * 255 / 100); if ([LxAlpha]::Get($w.Handle) -ne $want) { [void][LxAlpha]::Set($w.Handle, [int]$r.Opacity) } }
    }
}
# Reaplica alpha manual (setado pelo painel) caso algo sobrescreva (ex.: foco).
function Invoke-LxTranspManual {
    foreach ($w in [LxAlpha]::List()) {
        $m = [LxAlpha]::Manual($w.Handle)
        if ($m -ge 20 -and $m -lt 100) { $want = [int][Math]::Round($m * 255 / 100); if ([LxAlpha]::Get($w.Handle) -ne $want) { [void][LxAlpha]::Set($w.Handle, $m) } }
    }
}
