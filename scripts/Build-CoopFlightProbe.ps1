[CmdletBinding()]
param([string]$OutputRoot='', [string]$ValveHeaders='', [switch]$SkipBaselineChecks, [switch]$Menu, [switch]$Continuous)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
if ($Continuous) { $Menu=$true }
$revision=if ($Continuous) { 'r10' } elseif ($Menu) { 'r8' } else { 'r7' }
$source=if ($Continuous) { 'plane_coop_continuous_probe.cpp' } elseif ($Menu) { 'plane_coop_menu_probe.cpp' } else { 'plane_coop_probe.cpp' }
if (!$OutputRoot) { $OutputRoot=Join-Path $repo ('build\coop-flight-'+$revision) }
if (!$ValveHeaders) { $ValveHeaders=Join-Path $repo 'packages\valve-headers-d534' }
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$OutputRoot=(Resolve-Path -LiteralPath $OutputRoot).Path
if (!$SkipBaselineChecks) { & (Join-Path $PSScriptRoot 'Build-PlaneFlightProbe.ps1') -OutputRoot (Join-Path $OutputRoot 'baseline-checks') }
$vswhere=Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vs=& $vswhere -latest -prerelease -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (!$vs) { throw 'MSVC x64 toolchain missing' }
$dev=Join-Path $vs 'Common7\Tools\VsDevCmd.bat';$src=Join-Path $repo 'native'
$commands=@"
@echo off
call "$dev" -no_logo -arch=x64 -host_arch=x64
if not %errorlevel%==0 exit /b %errorlevel%
cl /nologo /std:c++17 /EHsc /W4 /WX /O2 /fp:strict /MT /c "$src\$source" /Fo:"$OutputRoot\flight.obj"
if not %errorlevel%==0 exit /b %errorlevel%
cl /nologo /std:c++17 /EHsc /W4 /WX /O2 /MT /external:I "$ValveHeaders" /external:W0 /c "$src\plane_coop_transport.cpp" /Fo:"$OutputRoot\transport.obj"
if not %errorlevel%==0 exit /b %errorlevel%
cl /nologo /LD /MT "$OutputRoot\flight.obj" "$OutputRoot\transport.obj" bcrypt.lib /Fe:"$OutputRoot\ac8_plane_coop_$revision.dll" /link /INCREMENTAL:NO
if not %errorlevel%==0 exit /b %errorlevel%
cl /nologo /std:c++17 /EHsc /W4 /WX /O2 /fp:strict /MT "$src\plane_coop_protocol_tests.cpp" /Fe:"$OutputRoot\plane_coop_protocol_tests.exe" /Fo:"$OutputRoot\protocol_tests.obj" /link /INCREMENTAL:NO
if not %errorlevel%==0 exit /b %errorlevel%
"$OutputRoot\plane_coop_protocol_tests.exe"
if not %errorlevel%==0 exit /b %errorlevel%
cl /nologo /std:c++17 /EHsc /W4 /WX /O2 /MT /external:I "$ValveHeaders" /external:W0 "$src\plane_coop_transport_tests.cpp" /Fe:"$OutputRoot\plane_coop_transport_tests.exe" /Fo:"$OutputRoot\transport_tests.obj" /link bcrypt.lib /INCREMENTAL:NO
if not %errorlevel%==0 exit /b %errorlevel%
"$OutputRoot\plane_coop_transport_tests.exe"
if not %errorlevel%==0 exit /b %errorlevel%
cl /nologo /std:c++17 /EHsc /W4 /WX /O2 /MT "$src\plane_coop_menu_config_tests.cpp" /Fe:"$OutputRoot\plane_coop_menu_config_tests.exe" /Fo:"$OutputRoot\menu_config_tests.obj" /link /INCREMENTAL:NO
if not %errorlevel%==0 exit /b %errorlevel%
"$OutputRoot\plane_coop_menu_config_tests.exe"
if not %errorlevel%==0 exit /b %errorlevel%
"@
[IO.File]::WriteAllText((Join-Path $OutputRoot 'build.cmd'),$commands,[Text.Encoding]::Default)
Push-Location $OutputRoot
try { & $env:ComSpec /d /c (Join-Path $OutputRoot 'build.cmd'); if ($LASTEXITCODE) { throw "$revision build failed: $LASTEXITCODE" }; Get-FileHash (Join-Path $OutputRoot "ac8_plane_coop_$revision.dll") } finally { Pop-Location }
