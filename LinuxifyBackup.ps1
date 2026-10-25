# Linuxify - backup manifest + PowerShell profile helpers shared by install.ps1 and uninstall.ps1. ASCII-only.
# Needs LinuxifyTerminal.ps1 (Read-LxText / Write-LxText) to be loaded first.
#
# backups.txt has one "original path|backup path" line per file Linuxify replaced. The FIRST line for a
# path is the state before Linuxify, and the only one the uninstaller restores. "@absent" as the backup
# path means the file did not exist before Linuxify created it.

$script:LxAbsent = '@absent'

function Get-LxFileEncoding([string]$Path) {
    # The encoding a text file is already in, so it can be edited and written back unchanged:
    # BOM -> that encoding; BOM-less valid UTF-8 (and pure ASCII) -> UTF-8; anything else -> the ANSI code page,
    # which is how Windows PowerShell 5.1 itself reads a file that has no BOM.
    $b = [IO.File]::ReadAllBytes($Path)
    if ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) { return (New-Object System.Text.UTF8Encoding($true)) }
    if ($b.Length -ge 2 -and $b[0] -eq 0xFF -and $b[1] -eq 0xFE) { return (New-Object System.Text.UnicodeEncoding($false, $true)) }
    if ($b.Length -ge 2 -and $b[0] -eq 0xFE -and $b[1] -eq 0xFF) { return (New-Object System.Text.UnicodeEncoding($true, $true)) }
    try { [void](New-Object System.Text.UTF8Encoding($false, $true)).GetString($b); return (New-Object System.Text.UTF8Encoding($false)) } catch {}
    try { return [System.Text.Encoding]::GetEncoding([Globalization.CultureInfo]::CurrentCulture.TextInfo.ANSICodePage) } catch { return [System.Text.Encoding]::GetEncoding(28591) }
}

function Read-LxTextFile([string]$Path) {
    $enc = Get-LxFileEncoding $Path
    [pscustomobject]@{ Text = [IO.File]::ReadAllText($Path, $enc); Encoding = $enc }
}

function Test-LxManifestHas([string]$Manifest, [string]$Path) {
    if (-not (Test-Path $Manifest)) { return $false }
    foreach ($l in (Read-LxTextFile $Manifest).Text -split "\r?\n") {
        if ($l -and (($l -split '\|', 2)[0] -ieq $Path)) { return $true }
    }
    return $false
}

function Add-LxManifest([string]$Manifest, [string]$Path, [string]$Backup) {
    $line = "$Path|$Backup`r`n"
    if (Test-Path $Manifest) { [IO.File]::AppendAllText($Manifest, $line, (Get-LxFileEncoding $Manifest)) }
    else { [IO.File]::WriteAllText($Manifest, $line, (New-Object System.Text.UTF8Encoding($true))) }
}

function Get-LxManifestEntries([string]$Manifest) {
    # first entry per path, in file order; each is @{ Path; Backup }
    $seen = @{}
    if (-not (Test-Path $Manifest)) { return @() }
    foreach ($l in (Read-LxTextFile $Manifest).Text -split "\r?\n") {
        if (-not $l) { continue }
        $p, $b = $l -split '\|', 2
        if ($seen.ContainsKey($p.ToLowerInvariant())) { continue }
        $seen[$p.ToLowerInvariant()] = $true
        [pscustomobject]@{ Path = $p; Backup = $b }
    }
}

function Backup-LxPath {
    # Records the state of $Path before Linuxify writes to it. Only the first time for a path: a later
    # backup would just be a copy of Linuxify's own output. A file that already equals what Linuxify
    # is about to write ($Replacement) has nothing worth saving either.
    param([string]$Path, [string]$DataDir, [string]$Stamp, [string]$Replacement)
    $manifest = Join-Path $DataDir 'backups.txt'
    if (Test-LxManifestHas $manifest $Path) { return }
    if (-not (Test-Path $Path)) { Add-LxManifest $manifest $Path $script:LxAbsent; return }
    if ($Replacement -and (Test-Path $Replacement -PathType Leaf) -and (Test-Path $Path -PathType Leaf) -and
        ((Get-FileHash $Path).Hash -eq (Get-FileHash $Replacement).Hash)) { return }
    $dir = Join-Path $DataDir ("backup\install-$Stamp")
    New-Item -ItemType Directory -Force $dir | Out-Null
    $dst = Join-Path $dir (($Path -replace '[:\\/]', '_').Trim('_'))
    Copy-Item $Path $dst -Recurse -Force
    Add-LxManifest $manifest $Path $dst
}

# ---- PowerShell profile hook -------------------------------------------------------------------
# Only lines Linuxify wrote are ever removed: the "# linuxify" marker and the line that loads
# Linuxify\shell\init.ps1. Nothing else in the profile (a user's own `starship init`, say) is touched.

function Get-LxProfileHookLines {
    @('# linuxify', '$__li = Join-Path $env:LOCALAPPDATA ''Linuxify\shell\init.ps1''; if (Test-Path $__li) { . $__li }')
}

function Test-LxProfileHookLine([string]$Line) {
    $t = $Line.Trim()
    return ($t -ceq '# linuxify') -or ($t -match '^(\.|\$__li\s*=).*Linuxify\\shell\\init\.ps1')
}

function Test-LxProfileHook([string]$Path) {
    if (-not (Test-Path $Path)) { return $false }
    foreach ($l in (Read-LxTextFile $Path).Text -split "\r?\n") { if (Test-LxProfileHookLine $l) { return $true } }
    return $false
}

function Add-LxProfileHook([string]$Path) {
    $parent = Split-Path $Path -Parent
    if ($parent) { New-Item -ItemType Directory -Force $parent | Out-Null }
    if (Test-Path $Path) {
        $f = Read-LxTextFile $Path
        $nl = if ($f.Text.Contains("`n") -and -not $f.Text.Contains("`r`n")) { "`n" } else { "`r`n" }   # follow the file's own line endings
        $hook = (Get-LxProfileHookLines) -join $nl
        $sep = if ($f.Text -and -not $f.Text.EndsWith("`n")) { $nl + $nl } else { $nl }
        [IO.File]::WriteAllText($Path, ($f.Text + $sep + $hook + $nl), $f.Encoding)
    } else {
        [IO.File]::WriteAllText($Path, (((Get-LxProfileHookLines) -join "`r`n") + "`r`n"), (New-Object System.Text.UTF8Encoding($true)))
    }
}

function Remove-LxProfileHook {
    # Returns $true if the file is now empty (only whitespace).
    param([string]$Path)
    $f = Read-LxTextFile $Path
    $lines = @($f.Text -split "\r?\n")
    $kept = @($lines | Where-Object { -not (Test-LxProfileHookLine $_) })
    if ($kept.Count -ne $lines.Count) {
        $nl = if ($f.Text.Contains("`r`n")) { "`r`n" } else { "`n" }
        $text = ($kept -join $nl).TrimEnd("`r", "`n")
        [IO.File]::WriteAllText($Path, $(if ($text) { $text + $nl } else { '' }), $f.Encoding)
    }
    return (-not (($kept -join '').Trim()))
}

function New-LxProfileCleanupCommand {
    # Script text for an elevated PowerShell that removes the hook from the all-users profile. It is passed
    # to powershell.exe as -EncodedCommand, so there is no script file that another process could replace
    # between the user's click and the UAC prompt being accepted.
    param([string]$Path)
    $q = $Path.Replace("'", "''")
    $fns = 'Get-LxFileEncoding', 'Read-LxTextFile', 'Test-LxProfileHookLine', 'Remove-LxProfileHook' | ForEach-Object {
        "function $_ {" + (Get-Command $_ -CommandType Function).ScriptBlock.ToString() + "}"
    }
    ($fns -join "`n") + "`n[void](Remove-LxProfileHook -Path '$q')"
}

function Invoke-LxElevatedProfileCleanup {
    param([string]$Path)
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes((New-LxProfileCleanupCommand -Path $Path)))
    Start-Process powershell -Verb RunAs -WindowStyle Hidden -Wait -ErrorAction Stop -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded
}
