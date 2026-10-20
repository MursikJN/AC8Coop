[CmdletBinding()]
param([string]$OutputRoot = 'D:\projects\unreal-mod-tools\build\steam-probe')
$ErrorActionPreference = 'Stop'
$sourceRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'native'
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$installation = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (!$installation) { throw 'Existing MSVC x64 build tools not found.' }
$devcmd = Join-Path $installation 'Common7\Tools\VsDevCmd.bat'
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
# Only compiler invocation uses cmd; all file operations stay in PowerShell.
$commands = @"
@echo off
call "$devcmd" -no_logo -arch=x64 -host_arch=x64
if errorlevel 1 exit /b 1
cl /nologo /W4 /WX /O2 /MT /LD "$sourceRoot\steam_probe.cpp" /Fe:"$OutputRoot\ac8_steam_probe.dll" /Fo:"$OutputRoot\steam_probe.obj" /link /INCREMENTAL:NO
if errorlevel 1 exit /b 1
cl /nologo /W4 /WX /O2 /MT "$sourceRoot\steam_probe_tests.cpp" /Fe:"$OutputRoot\steam_probe_tests.exe" /Fo:"$OutputRoot\steam_probe_tests.obj" /link /INCREMENTAL:NO
if errorlevel 1 exit /b 1
"$OutputRoot\steam_probe_tests.exe"
"@
$batchPath = Join-Path $OutputRoot 'build.cmd'
[IO.File]::WriteAllText($batchPath, $commands, [Text.Encoding]::Default)
Push-Location $OutputRoot
try {
    & $env:ComSpec /d /c $batchPath
    if ($LASTEXITCODE -ne 0) { throw "Build/test failed: $LASTEXITCODE" }
    Get-FileHash -LiteralPath (Join-Path $OutputRoot 'ac8_steam_probe.dll')
} finally { Pop-Location }
