[CmdletBinding()]
param([string]$OutputRoot='', [switch]$ModelTrial,[switch]$RoleBridge,[ValidatePattern('^r(?:17|18|19)[a-z]?$')][string]$TrialRevision='r17')
$ErrorActionPreference='Stop';$repo=Split-Path $PSScriptRoot -Parent
if($RoleBridge){$ModelTrial=$true;if(!$PSBoundParameters.ContainsKey('TrialRevision')){$TrialRevision='r18'}}
$revision=if($ModelTrial){$TrialRevision}else{'r16'};$DllName='ac8_guest_player_init_'+$revision+'.dll'
if(!$OutputRoot){$OutputRoot=Join-Path $repo ('build\guest-player-'+$revision)}
New-Item -ItemType Directory -Force -Path $OutputRoot|Out-Null;$OutputRoot=(Resolve-Path $OutputRoot).Path
$vswhere=Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vs=& $vswhere -latest -prerelease -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if(!$vs){throw 'MSVC missing'};$dev=Join-Path $vs 'Common7\Tools\VsDevCmd.bat';$src=Join-Path $repo 'native'
$lines=@('@echo off',('call "'+$dev+'" -no_logo -arch=x64 -host_arch=x64'),'if not %errorlevel%==0 exit /b %errorlevel%')
$lines+=('cl /nologo /std:c++17 /EHsc /W4 /WX /O2 /MT "'+$src+'\plane_flight_tests.cpp" /Fe:"'+$OutputRoot+'\plane_flight_tests.exe" /Fo:"'+$OutputRoot+'\tests.obj" /link /INCREMENTAL:NO')
$lines+='if not %errorlevel%==0 exit /b %errorlevel%';$lines+=('"'+$OutputRoot+'\plane_flight_tests.exe"');$lines+='if not %errorlevel%==0 exit /b %errorlevel%'
$lines+=('cl /nologo /std:c++17 /EHsc /W4 /WX /O2 /MT "'+$src+'\guest_player_physics_tests.cpp" /Fe:"'+$OutputRoot+'\guest_player_physics_tests.exe" /Fo:"'+$OutputRoot+'\physics-tests.obj" /link /INCREMENTAL:NO')
$lines+='if not %errorlevel%==0 exit /b %errorlevel%';$lines+=('"'+$OutputRoot+'\guest_player_physics_tests.exe"');$lines+='if not %errorlevel%==0 exit /b %errorlevel%'
$lines+=('cl /nologo /std:c++17 /EHsc /W4 /WX /O2 /MT "'+$src+'\guest_role_tests.cpp" /Fe:"'+$OutputRoot+'\guest_role_tests.exe" /Fo:"'+$OutputRoot+'\role-tests.obj" /link /INCREMENTAL:NO')
$lines+='if not %errorlevel%==0 exit /b %errorlevel%';$lines+=('"'+$OutputRoot+'\guest_role_tests.exe"');$lines+='if not %errorlevel%==0 exit /b %errorlevel%'
$entry=if($RoleBridge){'guest_player_role.cpp'}elseif($ModelTrial){'guest_player_model.cpp'}else{'guest_player_initialize.cpp'}
$defines=if($ModelTrial){' /DAC8_GUEST_MODEL_REV='+$TrialRevision}else{''}
$lines+=('cl /nologo /std:c++17 /EHsc /W4 /WX /O2 /MT /Zi /LD'+$defines+' "'+$src+'\'+$entry+'" dbghelp.lib /Fe:"'+$OutputRoot+'\'+$DllName+'" /Fo:"'+$OutputRoot+'\stage.obj" /link /DEBUG /INCREMENTAL:NO')
$lines+='exit /b %errorlevel%'
[IO.File]::WriteAllLines((Join-Path $OutputRoot 'build.cmd'),$lines,[Text.Encoding]::Default)
Push-Location $OutputRoot
try{& $env:ComSpec /d /c (Join-Path $OutputRoot 'build.cmd');if($LASTEXITCODE){throw "Guest player build failed: $LASTEXITCODE"};Get-FileHash (Join-Path $OutputRoot $DllName)}finally{Pop-Location}
