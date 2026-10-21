[CmdletBinding()]
param([string]$OutputRoot='', [ValidatePattern('^ac8_menu_route_r(?:9|13)[a-z]?\.dll$')][string]$DllName='ac8_menu_route_r9.dll')
$ErrorActionPreference='Stop';$repo=Split-Path $PSScriptRoot -Parent
if (!$OutputRoot) { $OutputRoot=Join-Path $repo 'build\menu-route-r9' }
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null;$OutputRoot=(Resolve-Path $OutputRoot).Path
$vswhere=Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vs=& $vswhere -latest -prerelease -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (!$vs) { throw 'MSVC missing' };$dev=Join-Path $vs 'Common7\Tools\VsDevCmd.bat';$src=Join-Path $repo 'native\menu_route_probe.cpp'
$batch=@"
@echo off
call "$dev" -no_logo -arch=x64 -host_arch=x64
if not %errorlevel%==0 exit /b %errorlevel%
cl /nologo /std:c++17 /EHsc /W4 /WX /O2 /MT /LD "$src" /Fe:"$OutputRoot\$DllName" /Fo:"$OutputRoot\route.obj" /link /INCREMENTAL:NO
if not %errorlevel%==0 exit /b %errorlevel%
cl /nologo /std:c++17 /EHsc /W4 /WX /O2 /MT "$(Join-Path $repo 'native\menu_route_contract_tests.cpp')" /Fe:"$OutputRoot\menu_route_contract_tests.exe" /Fo:"$OutputRoot\tests.obj" /link /INCREMENTAL:NO
if not %errorlevel%==0 exit /b %errorlevel%
"$OutputRoot\menu_route_contract_tests.exe"
if not %errorlevel%==0 exit /b %errorlevel%
"@
[IO.File]::WriteAllText((Join-Path $OutputRoot 'build-route.cmd'),$batch,[Text.Encoding]::Default)
Push-Location $OutputRoot
try { & $env:ComSpec /d /c (Join-Path $OutputRoot 'build-route.cmd');if ($LASTEXITCODE) { throw "Route build failed: $LASTEXITCODE" };Get-FileHash (Join-Path $OutputRoot $DllName) } finally { Pop-Location }
