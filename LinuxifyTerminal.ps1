# Linuxify - Windows Terminal + text helpers shared by install.ps1 and Linuxify.ps1. ASCII-only.
# Windows PowerShell 5.1 reads BOM-less files as ANSI and writes ANSI by default, which corrupts
# non-ASCII text in files other tools (Windows Terminal, editors) wrote as UTF-8. Everything here
# goes through .NET with an explicit UTF-8 encoding instead of Get-Content / Set-Content.

function Read-LxText([string]$Path) {
    # UTF-8 (BOM detected and removed if present)
    [IO.File]::ReadAllText($Path, (New-Object System.Text.UTF8Encoding($false)))
}

function Write-LxText([string]$Path, [string]$Text, [bool]$Bom = $false) {
    # $Bom = $true for files Windows PowerShell 5.1 itself reads (profiles): without a BOM it would read UTF-8 as ANSI.
    [IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($Bom)))
}

function Test-LxJsonHasComments([string]$Text) {
    # Windows Terminal accepts // and /* */ comments. ConvertFrom-Json drops them (PowerShell 7) or fails
    # (Windows PowerShell 5.1); either way writing the result back would lose the user's notes.
    $noStrings = [regex]::Replace($Text, '"(?:[^"\\]|\\.)*"', '""')
    return ($noStrings -match '//|/\*')
}

function Build-LxTerminalVariant {
    # Writes $To = the Windows Terminal settings in $From with the Linuxify scheme and defaults added.
    # Only those keys are touched, so profiles, actions, keybindings and everything else in $From stay.
    # Throws if $From has comments or is otherwise not plain JSON, rather than rewriting it lossily.
    param([Parameter(Mandatory)][string]$From, [Parameter(Mandatory)][string]$To, [Parameter(Mandatory)][string]$OverlayDir)
    $text   = Read-LxText $From
    if (Test-LxJsonHasComments $text) { throw "$From contains comments, which cannot be edited without losing them." }
    $o      = $text | ConvertFrom-Json
    $scheme = Read-LxText (Join-Path $OverlayDir 'catppuccin-mocha.json') | ConvertFrom-Json
    $glob   = Read-LxText (Join-Path $OverlayDir 'global.json') | ConvertFrom-Json
    $defs   = Read-LxText (Join-Path $OverlayDir 'profile-defaults.json') | ConvertFrom-Json
    if (-not $o.PSObject.Properties['schemes']) { $o | Add-Member -NotePropertyName schemes -NotePropertyValue @() }
    $o.schemes = @(@($o.schemes | Where-Object { $_.name -ne $scheme.name }) + $scheme)
    foreach ($p in $glob.PSObject.Properties) { $o | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force }
    if (-not $o.PSObject.Properties['profiles']) { $o | Add-Member -NotePropertyName profiles -NotePropertyValue ([pscustomobject]@{}) }
    if (-not $o.profiles.PSObject.Properties['defaults']) { $o.profiles | Add-Member -NotePropertyName defaults -NotePropertyValue ([pscustomobject]@{}) }
    foreach ($p in $defs.PSObject.Properties) { $o.profiles.defaults | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force }
    Write-LxText $To ($o | ConvertTo-Json -Depth 32)
}

function Backup-LxTerminalEdits {
    # If Windows Terminal's settings differ from the Linux variant Linuxify wrote, the user (or the panel)
    # changed them while Linux mode was on. Keep a copy before the original is put back; keep the last 5.
    param([string]$WtSettings, [string]$LinuxVariant, [string]$BackupDir)
    if (-not ((Test-Path $WtSettings) -and (Test-Path $LinuxVariant))) { return $null }
    if ((Get-FileHash $WtSettings).Hash -eq (Get-FileHash $LinuxVariant).Hash) { return $null }
    New-Item -ItemType Directory -Force $BackupDir | Out-Null
    $bk = Join-Path $BackupDir ('wt-while-on-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.json')
    Copy-Item $WtSettings $bk -Force
    Get-ChildItem $BackupDir -Filter 'wt-while-on-*.json' | Sort-Object Name -Descending | Select-Object -Skip 5 | Remove-Item -Force -ErrorAction SilentlyContinue
    return $bk
}
