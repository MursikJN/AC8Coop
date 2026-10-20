[CmdletBinding()]
param([string]$OutputRoot = 'D:\projects\unreal-mod-tools\build\plane-flight-probe')
$ErrorActionPreference = 'Stop'
$sourceRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'native'
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$installation = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (!$installation) { throw 'Existing MSVC x64 build tools not found.' }
$devcmd = Join-Path $installation 'Common7\Tools\VsDevCmd.bat'
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $OutputRoot 'observation-fixtures') -Force | Out-Null
$commands = @"
@echo off
call "$devcmd" -no_logo -arch=x64 -host_arch=x64
if errorlevel 1 exit /b 1
cl /nologo /std:c++17 /EHsc /W4 /WX /O2 /fp:strict /MT /LD "$sourceRoot\plane_flight_probe.cpp" /Fe:"$OutputRoot\ac8_plane_flight_probe_r4.dll" /Fo:"$OutputRoot\plane_flight_probe.obj" /link /INCREMENTAL:NO
if errorlevel 1 exit /b 1
cl /nologo /std:c++17 /EHsc /W4 /WX /O2 /fp:strict /MT "$sourceRoot\plane_flight_tests.cpp" /Fe:"$OutputRoot\plane_flight_tests.exe" /Fo:"$OutputRoot\plane_flight_tests.obj" /link /INCREMENTAL:NO
if errorlevel 1 exit /b 1
"$OutputRoot\plane_flight_tests.exe"
if errorlevel 1 exit /b 1
cl /nologo /std:c++17 /EHsc /W4 /WX /O2 /fp:strict /MT "$sourceRoot\plane_flight_state_tests.cpp" /Fe:"$OutputRoot\plane_flight_state_tests.exe" /Fo:"$OutputRoot\plane_flight_state_tests.obj" /link /INCREMENTAL:NO
if errorlevel 1 exit /b 1
"$OutputRoot\plane_flight_state_tests.exe"
if errorlevel 1 exit /b 1
cl /nologo /std:c++17 /EHsc /W4 /WX /O2 /fp:strict /MT "$sourceRoot\plane_flight_slots_tests.cpp" /Fe:"$OutputRoot\plane_flight_slots_tests.exe" /Fo:"$OutputRoot\plane_flight_slots_tests.obj" /link /INCREMENTAL:NO
if errorlevel 1 exit /b 1
"$OutputRoot\plane_flight_slots_tests.exe"
if errorlevel 1 exit /b 1
cl /nologo /std:c++17 /EHsc /W4 /WX /O2 /fp:strict /MT "$sourceRoot\plane_component_ticks_tests.cpp" /Fe:"$OutputRoot\plane_component_ticks_tests.exe" /Fo:"$OutputRoot\plane_component_ticks_tests.obj" /link /INCREMENTAL:NO
if errorlevel 1 exit /b 1
"$OutputRoot\plane_component_ticks_tests.exe"
if errorlevel 1 exit /b 1
cl /nologo /std:c++17 /EHsc /W4 /WX /O2 /fp:strict /MT "$sourceRoot\plane_flight_observations_tests.cpp" /Fe:"$OutputRoot\plane_flight_observations_tests.exe" /Fo:"$OutputRoot\plane_flight_observations_tests.obj" /link /INCREMENTAL:NO
if errorlevel 1 exit /b 1
"$OutputRoot\plane_flight_observations_tests.exe" "$OutputRoot\observation-fixtures"
"@
$batchPath = Join-Path $OutputRoot 'build.cmd'
[IO.File]::WriteAllText($batchPath, $commands, [Text.Encoding]::Default)
Push-Location $OutputRoot
try {
    & $env:ComSpec /d /c $batchPath
    if ($LASTEXITCODE -ne 0) { throw "Build/test failed: $LASTEXITCODE" }
    Get-FileHash -LiteralPath (Join-Path $OutputRoot 'ac8_plane_flight_probe_r4.dll')
} finally { Pop-Location }
