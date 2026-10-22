<#
.SYNOPSIS Linuxify - i18n helper. ASCII-only; strings live in lang\*.json (UTF-8).
  Keys are the English texts. T 'text' returns the translation for the current language.
#>
$global:LxLangs = [ordered]@{ 'en' = 'English'; 'pt-BR' = 'Portugues (Brasil)'; 'es' = 'Espanol'; 'ru' = 'Russkiy' }
function Get-LxLangDir {
    foreach ($d in @((Join-Path $PSScriptRoot 'lang'), (Join-Path $env:LOCALAPPDATA 'Linuxify\lang'))) { if (Test-Path $d) { return $d } }
    return (Join-Path $PSScriptRoot 'lang')
}
function Get-LxDefaultLang {
    $c = [System.Globalization.CultureInfo]::CurrentUICulture.Name
    if ($c -like 'pt*') { 'pt-BR' } elseif ($c -like 'es*') { 'es' } elseif ($c -like 'ru*') { 'ru' } else { 'en' }
}
function Get-LxLang {
    $p = Join-Path $env:LOCALAPPDATA 'Linuxify\panel.json'
    if (Test-Path $p) { try { $l = ([IO.File]::ReadAllText($p) | ConvertFrom-Json).Lang; if ($l -and $global:LxLangs.Contains([string]$l)) { return [string]$l } } catch {} }
    Get-LxDefaultLang
}
function Read-LxLangFile([string]$code) {
    $h = @{}; $f = Join-Path (Get-LxLangDir) "$code.json"
    if (Test-Path $f) { try { $o = [IO.File]::ReadAllText($f, [System.Text.Encoding]::UTF8) | ConvertFrom-Json; foreach ($p in $o.PSObject.Properties) { $h[$p.Name] = [string]$p.Value } } catch {} }
    $h
}
function Import-LxLang([string]$code = '') {
    if (-not $code) { $code = Get-LxLang }
    $global:LxLang = $code; $global:LxEn = Read-LxLangFile 'en'; $global:LxStr = if ($code -eq 'en') { $global:LxEn } else { Read-LxLangFile $code }
    # display names with native script come from the json too
    foreach ($k in @($global:LxLangs.Keys)) { $n = (Read-LxLangFile $k)['@name']; if ($n) { $global:LxLangs[$k] = $n } }
}
function T([string]$k) {
    if ($global:LxStr -and $global:LxStr.ContainsKey($k) -and $global:LxStr[$k]) { return $global:LxStr[$k] }
    if ($global:LxEn -and $global:LxEn.ContainsKey($k) -and $global:LxEn[$k]) { return $global:LxEn[$k] }
    $k
}
Import-LxLang
