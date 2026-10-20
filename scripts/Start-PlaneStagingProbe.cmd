@echo off
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Launch-Recon.ps1" -PlaneStaging
set "probeExit=%errorlevel%"
echo.
echo Research launcher finished. Check loader cleanup before ordinary play.
pause
exit /b %probeExit%
