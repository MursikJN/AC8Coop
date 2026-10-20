@echo off
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Launch-Recon.ps1" -ReadOnlyProbe plane_initialization_probe.lua
set "probeExit=%errorlevel%"
echo.
echo Research launcher finished. Check the cleanup message before ordinary play.
pause
exit /b %probeExit%
