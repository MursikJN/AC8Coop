@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Start-LocalCoop.ps1" -GuestSimulator -HangarAdapter -Width 1280 -Height 720
pause
