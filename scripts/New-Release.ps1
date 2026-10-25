<#
.SYNOPSIS
  Builds the release zip and its SHA256SUMS file.
.DESCRIPTION
  Packs the files install.ps1 needs into dist\Linuxify-<Version>.zip (plus Linuxify.exe when -Exe is
  given), then writes dist\SHA256SUMS in the format `sha256sum -c` reads:  <hash>  <file name>.
  Publish the zip, the exe (if any) and SHA256SUMS together. Users check a download with
    Get-FileHash .\Linuxify-<Version>.zip -Algorithm SHA256
  and compare it with the line in SHA256SUMS.
.PARAMETER Version  Release version, for example 0.2.5 (becomes part of the zip name).
.PARAMETER Exe      Optional path to a built Linuxify.exe to include in the zip and the checksum list.
.PARAMETER OutDir   Output folder (default: dist next to the repository root).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^\d+\.\d+\.\d+([-.][0-9A-Za-z.]+)?$')][string]$Version,
    [string]$Exe,
    [string]$OutDir
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if (-not $OutDir) { $OutDir = Join-Path $root 'dist' }

function Get-LxReleaseFile {
    # Paths relative to $Root, forward slashes: what goes into the zip.
    param([string]$Root)
    $top = Get-ChildItem $Root -File | Where-Object { $_.Extension -in '.ps1', '.cmd', '.md' -or $_.Name -eq 'LICENSE' }
    $dirs = 'configs', 'lang', 'assets' | ForEach-Object { Get-ChildItem (Join-Path $Root $_) -Recurse -File }
    foreach ($f in @($top) + @($dirs)) { $f.FullName.Substring($Root.Length).TrimStart('\', '/').Replace('\', '/') }
}

function Format-LxChecksum([string]$Path) {
    # sha256sum format: lowercase hex, two spaces, file name
    $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    '{0}  {1}' -f $hash, (Split-Path $Path -Leaf)
}

if ($Exe -and -not (Test-Path -LiteralPath $Exe)) { throw "Exe not found: $Exe" }
New-Item -ItemType Directory -Force $OutDir | Out-Null
$zip = Join-Path $OutDir "Linuxify-$Version.zip"
Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue

Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::Open($zip, 'Create')
try {
    $entries = [ordered]@{}
    foreach ($rel in Get-LxReleaseFile $root) { $entries[$rel] = Join-Path $root $rel }
    if ($Exe) { $entries['Linuxify.exe'] = (Resolve-Path -LiteralPath $Exe).Path }
    foreach ($kv in $entries.GetEnumerator()) {
        [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $kv.Value, $kv.Key, 'Optimal')
    }
} finally { $archive.Dispose() }

$files = @($zip)
if ($Exe) {
    $exeCopy = Join-Path $OutDir 'Linuxify.exe'
    if ((Resolve-Path -LiteralPath $Exe).Path -ne (Resolve-Path -LiteralPath $exeCopy -ErrorAction SilentlyContinue).Path) { Copy-Item -LiteralPath $Exe $exeCopy -Force }
    $files += $exeCopy
}
$sums = Join-Path $OutDir 'SHA256SUMS'
[IO.File]::WriteAllText($sums, ((($files | ForEach-Object { Format-LxChecksum $_ }) -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Wrote $zip"
Write-Host "Wrote $sums"
Get-Content $sums | ForEach-Object { Write-Host "  $_" }
