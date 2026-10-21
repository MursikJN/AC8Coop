[CmdletBinding()]
param([string]$OutputRoot='')
$ErrorActionPreference='Stop';$repo=Split-Path $PSScriptRoot -Parent
if(!$OutputRoot){$OutputRoot=Join-Path $repo 'build\scene-r21'}
New-Item -ItemType Directory -Force -Path $OutputRoot|Out-Null;$OutputRoot=(Resolve-Path $OutputRoot).Path
$vswhere=Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vs=& $vswhere -latest -prerelease -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if(!$vs){throw 'MSVC missing'};$dev=Join-Path $vs 'Common7\Tools\VsDevCmd.bat';$src=Join-Path $repo 'native';$headers=Join-Path $repo 'packages\valve-headers-d534'
$lines=@('@echo off',('call "'+$dev+'" -no_logo -arch=x64 -host_arch=x64'),'if not %errorlevel%==0 exit /b %errorlevel%')
$lines+=('cl /nologo /std:c++17 /EHsc /W4 /WX /O2 /MT /external:I "'+$headers+'" /external:W0 "'+$src+'\scene_transport_tests.cpp" bcrypt.lib /Fe:"'+$OutputRoot+'\scene_transport_tests.exe" /Fo:"'+$OutputRoot+'\tests.obj" /link /INCREMENTAL:NO')
$lines+='if not %errorlevel%==0 exit /b %errorlevel%';$lines+=('"'+$OutputRoot+'\scene_transport_tests.exe"');$lines+='if not %errorlevel%==0 exit /b %errorlevel%'
$lines+=('cl /nologo /std:c++17 /EHsc /W4 /WX /O2 /MT /Zi /external:I "'+$headers+'" /external:W0 /LD "'+$src+'\scene_bridge.cpp" bcrypt.lib /Fe:"'+$OutputRoot+'\ac8_scene_r21.dll" /Fo:"'+$OutputRoot+'\scene.obj" /link /DEBUG /INCREMENTAL:NO')
$lines+='exit /b %errorlevel%';[IO.File]::WriteAllLines((Join-Path $OutputRoot 'build.cmd'),$lines,[Text.Encoding]::Default)
Push-Location $OutputRoot
try{& $env:ComSpec /d /c (Join-Path $OutputRoot 'build.cmd');if($LASTEXITCODE){throw "Scene build failed: $LASTEXITCODE"};Get-FileHash (Join-Path $OutputRoot 'ac8_scene_r21.dll')}finally{Pop-Location}
