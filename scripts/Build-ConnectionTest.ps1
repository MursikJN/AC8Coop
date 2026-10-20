[CmdletBinding()]
param([string]$OutputRoot='D:\projects\unreal-mod-tools\build\connection-test',
      [string]$ValveHeaders='D:\projects\unreal-mod-tools\references\valve-networking-headers')
$ErrorActionPreference='Stop'
$sourceRoot=Join-Path (Split-Path $PSScriptRoot -Parent) 'native'
$vswhere=Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$installation=& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (!$installation) { throw 'MSVC x64 build tools not found.' }
$devcmd=Join-Path $installation 'Common7\Tools\VsDevCmd.bat'
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
$commands=@"
@echo off
call "$devcmd" -no_logo -arch=x64 -host_arch=x64
if errorlevel 1 exit /b 1
cl /nologo /std:c++17 /EHsc /W4 /WX /O2 /MT /external:I "$ValveHeaders" /external:W0 /LD "$sourceRoot\connection_test.cpp" /Fe:"$OutputRoot\ac8_connection_test.dll" /Fo:"$OutputRoot\connection_test.obj" /link bcrypt.lib /INCREMENTAL:NO
if errorlevel 1 exit /b 1
cl /nologo /std:c++17 /EHsc /W4 /WX /O2 /MT "$sourceRoot\connection_protocol_tests.cpp" /Fe:"$OutputRoot\connection_protocol_tests.exe" /Fo:"$OutputRoot\connection_protocol_tests.obj" /link /INCREMENTAL:NO
if errorlevel 1 exit /b 1
"$OutputRoot\connection_protocol_tests.exe"
if errorlevel 1 exit /b 1
cl /nologo /std:c++17 /EHsc /W4 /WX /O2 /MT /external:I "$ValveHeaders" /external:W0 "$sourceRoot\connection_runtime_tests.cpp" /Fe:"$OutputRoot\connection_runtime_tests.exe" /Fo:"$OutputRoot\connection_runtime_tests.obj" /link bcrypt.lib /INCREMENTAL:NO
if errorlevel 1 exit /b 1
"$OutputRoot\connection_runtime_tests.exe"
"@
$batch=Join-Path $OutputRoot 'build.cmd'
[IO.File]::WriteAllText($batch,$commands,[Text.Encoding]::Default)
Push-Location $OutputRoot
try {
 & $env:ComSpec /d /c $batch
 if($LASTEXITCODE -ne 0) { throw "Build or tests failed: $LASTEXITCODE" }
 Get-FileHash -LiteralPath (Join-Path $OutputRoot 'ac8_connection_test.dll')
} finally {Pop-Location}
