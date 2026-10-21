@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Start-LocalCoop.ps1" -GuestSimulator -HangarAdapter -MissionSync -AdapterDevelopment
if errorlevel 1 pause
