[CmdletBinding()]
param([string]$OutputRoot='')
$ErrorActionPreference='Stop';$repo=Split-Path $PSScriptRoot -Parent
if(!$OutputRoot){$OutputRoot=Join-Path $repo 'build/steam-lobby-r25'}
New-Item -ItemType Directory -Force -Path $OutputRoot|Out-Null;$OutputRoot=(Resolve-Path $OutputRoot).Path
$vswhere=Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$vs=& $vswhere -latest -prerelease -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if(!$vs){throw 'MSVC missing'};$dev=Join-Path $vs 'Common7/Tools/VsDevCmd.bat';$src=Join-Path $repo 'native';$headers=Join-Path $repo 'packages/valve-headers-d534'
$lines=@('@echo off',('call "'+$dev+'" -no_logo -arch=x64 -host_arch=x64'),'if not %errorlevel%==0 exit /b %errorlevel%')
foreach($unit in @('steam_lobby_tests','shared_session_transport_tests','steam_invite_tests')){
 $lines+=('cl /nologo /std:c++17 /EHsc /W4 /WX /O2 /MT /external:I "'+$headers+'" /external:W0 "'+$src+'/'+$unit+'.cpp" bcrypt.lib /Fe:"'+$OutputRoot+'/'+$unit+'.exe" /Fo:"'+$OutputRoot+'/'+$unit+'.obj" /link /INCREMENTAL:NO')
 $lines+='if not %errorlevel%==0 exit /b %errorlevel%';$lines+=('"'+$OutputRoot+'/'+$unit+'.exe"');$lines+='if not %errorlevel%==0 exit /b %errorlevel%'
}
$lines+=('cl /nologo /std:c++17 /EHsc /W4 /WX /O2 /MT /Zi /DAC8_STEAM_INVITES_R25 /external:I "'+$headers+'" /external:W0 /LD "'+$src+'/steam_lobby_bridge.cpp" bcrypt.lib /Fe:"'+$OutputRoot+'/ac8_steam_lobby_r25.dll" /Fo:"'+$OutputRoot+'/bridge.obj" /link /DEBUG /INCREMENTAL:NO')
$lines+='exit /b %errorlevel%';[IO.File]::WriteAllLines((Join-Path $OutputRoot 'build.cmd'),$lines,[Text.Encoding]::Default)
Push-Location $OutputRoot
try{& $env:ComSpec /d /c (Join-Path $OutputRoot 'build.cmd');if($LASTEXITCODE){throw "Steam lobby build failed: $LASTEXITCODE"};Get-FileHash (Join-Path $OutputRoot 'ac8_steam_lobby_r25.dll')}finally{Pop-Location}
