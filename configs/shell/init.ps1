# Linuxify shell init (fora do OneDrive). Carregado pelo profile AllUsers ($PSHOME\profile.ps1) e pelos perfis do WT.
if ($global:__linuxifyInit) { return }; $global:__linuxifyInit = $true
$__st = Join-Path $env:LOCALAPPDATA 'Linuxify\state.txt'
if (-not ((Test-Path $__st) -and ((Get-Content $__st -Raw).Trim() -eq 'on'))) { return }
$__a = [Environment]::GetCommandLineArgs()
if (-not [Environment]::UserInteractive -or ($__a -match '^-NonI') -or (($__a -match '^-(c|Command|f|File|e|EncodedCommand)$') -and -not ($__a -match '^-NoE'))) { return }
$env:STARSHIP_CONFIG = Join-Path $HOME '.config\starship.toml'
if ((Get-Location).Path -ieq "$env:SystemRoot\System32") { Set-Location $HOME }
if (Get-Command starship -ErrorAction SilentlyContinue) { Invoke-Expression (& starship init powershell --print-full-init | Out-String) }
if ($env:WT_SESSION -and -not $env:LINUXIFY_NOFETCH -and (Get-Command fastfetch -ErrorAction SilentlyContinue)) { Clear-Host; fastfetch }
