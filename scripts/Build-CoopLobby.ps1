[CmdletBinding()]
param([string]$OutputRoot='')
$ErrorActionPreference='Stop';$repo=Split-Path $PSScriptRoot -Parent
if (!$OutputRoot) { $OutputRoot=Join-Path $repo 'build\coop-lobby-r9' }
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$OutputRoot=(Resolve-Path $OutputRoot).Path
$vswhere=Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vs=& $vswhere -latest -prerelease -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (!$vs) { throw 'MSVC missing' }
$dev=Join-Path $vs 'Common7\Tools\VsDevCmd.bat';$src=Join-Path $repo 'native';$headers=Join-Path $repo 'packages\valve-headers-d534'
$batch=@"
@echo off
call "$dev" -no_logo -arch=x64 -host_arch=x64
if not %errorlevel%==0 exit /b %errorlevel%
cl /nologo /std:c++17 /EHsc /W4 /WX /O2 /MT /external:I "$headers" /external:W0 /LD "$src\coop_lobby_bridge.cpp" bcrypt.lib /Fe:"$OutputRoot\ac8_coop_lobby_r9.dll" /Fo:"$OutputRoot\lobby.obj" /link /INCREMENTAL:NO
if not %errorlevel%==0 exit /b %errorlevel%
cl /nologo /std:c++17 /EHsc /W4 /WX /O2 /MT /external:I "$headers" /external:W0 "$src\coop_lobby_tests.cpp" bcrypt.lib /Fe:"$OutputRoot\coop_lobby_tests.exe" /Fo:"$OutputRoot\tests.obj" /link /INCREMENTAL:NO
if not %errorlevel%==0 exit /b %errorlevel%
"$OutputRoot\coop_lobby_tests.exe"
if not %errorlevel%==0 exit /b %errorlevel%
"@
[IO.File]::WriteAllText((Join-Path $OutputRoot 'build.cmd'),$batch,[Text.Encoding]::Default)
Push-Location $OutputRoot
try { & $env:ComSpec /d /c (Join-Path $OutputRoot 'build.cmd');if ($LASTEXITCODE) { throw "Lobby build failed: $LASTEXITCODE" };Get-FileHash (Join-Path $OutputRoot 'ac8_coop_lobby_r9.dll') } finally { Pop-Location }
