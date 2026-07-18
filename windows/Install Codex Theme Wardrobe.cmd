@echo off
setlocal
set "INSTALLER=%~dp0windows\scripts\install-dream-skin.ps1"
if not exist "%INSTALLER%" set "INSTALLER=%~dp0scripts\install-dream-skin.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%INSTALLER%"
if errorlevel 1 pause
