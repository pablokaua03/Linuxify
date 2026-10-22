@echo off
if exist "%LOCALAPPDATA%\Linuxify\uninstall.ps1" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%LOCALAPPDATA%\Linuxify\uninstall.ps1" %*
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1" %*
)
pause
