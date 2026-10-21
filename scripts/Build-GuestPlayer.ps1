[CmdletBinding()]
param([string]$OutputRoot='', [ValidatePattern('^ac8_guest_player_stage_r15[a-z]?\.dll$')][string]$DllName='ac8_guest_player_stage_r15.dll')
$ErrorActionPreference='Stop';$repo=Split-Path $PSScriptRoot -Parent
if(!$OutputRoot){$OutputRoot=Join-Path $repo 'build\guest-player-r15'}
New-Item -ItemType Directory -Force -Path $OutputRoot|Out-Null;$OutputRoot=(Resolve-Path $OutputRoot).Path
$vswhere=Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vs=& $vswhere -latest -prerelease -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if(!$vs){throw 'MSVC missing'};$dev=Join-Path $vs 'Common7\Tools\VsDevCmd.bat';$src=Join-Path $repo 'native'
$lines=@('@echo off',('call "'+$dev+'" -no_logo -arch=x64 -host_arch=x64'),'if not %errorlevel%==0 exit /b %errorlevel%')
$lines+=('cl /nologo /std:c++17 /EHsc /W4 /WX /O2 /MT "'+$src+'\guest_player_stage_tests.cpp" /Fe:"'+$OutputRoot+'\guest_player_stage_tests.exe" /Fo:"'+$OutputRoot+'\tests.obj" /link /INCREMENTAL:NO')
$lines+='if not %errorlevel%==0 exit /b %errorlevel%';$lines+=('"'+$OutputRoot+'\guest_player_stage_tests.exe"');$lines+='if not %errorlevel%==0 exit /b %errorlevel%'
$lines+=('cl /nologo /std:c++17 /EHsc /W4 /WX /O2 /MT /LD "'+$src+'\guest_player_stage.cpp" /Fe:"'+$OutputRoot+'\'+$DllName+'" /Fo:"'+$OutputRoot+'\stage.obj" /link /INCREMENTAL:NO')
$lines+='exit /b %errorlevel%'
[IO.File]::WriteAllLines((Join-Path $OutputRoot 'build.cmd'),$lines,[Text.Encoding]::Default)
Push-Location $OutputRoot
try{& $env:ComSpec /d /c (Join-Path $OutputRoot 'build.cmd');if($LASTEXITCODE){throw "Guest player build failed: $LASTEXITCODE"};Get-FileHash (Join-Path $OutputRoot $DllName)}finally{Pop-Location}
