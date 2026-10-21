[CmdletBinding()]
param([switch]$SkipTests,[ValidateSet('r27','r28','r29')][string]$Revision='r27')
$ErrorActionPreference='Stop';$repo=Split-Path $PSScriptRoot -Parent;$out=Join-Path $repo ('build/steam-coop-'+$Revision)
New-Item -ItemType Directory -Force -Path $out|Out-Null
$vswhere=Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$vs=& $vswhere -latest -prerelease -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if(!$vs){throw 'MSVC missing'};$dev=Join-Path $vs 'Common7/Tools/VsDevCmd.bat';$src=Join-Path $repo 'native';$headers=Join-Path $repo 'packages/valve-headers-d534'
$lines=@('@echo off',('call "'+$dev+'" -no_logo -arch=x64 -host_arch=x64'),'if not %errorlevel%==0 exit /b %errorlevel%')
$units=@('steam_coop_tests','guest_pilot_tests','mission_pause_lease_tests');if($Revision -ne 'r27'){$units+='cinema_sync_tests'};if($Revision -eq 'r29'){$units+='session_policy_tests'}
if(!$SkipTests){foreach($unit in $units){
 $defines=if($unit -eq 'guest_pilot_tests'){' /DAC8_STEAM_COOP_R27 /DAC8_MISSION_SYNC_R26'}else{''}
 $lines+=('cl /nologo /std:c++17 /EHsc /W4 /WX /O2 /MT'+$defines+' "'+$src+'/'+$unit+'.cpp" /Fe:"'+$out+'/'+$unit+'.exe" /Fo:"'+$out+'/'+$unit+'.obj"')
 $lines+='if not %errorlevel%==0 exit /b %errorlevel%';$lines+=('"'+$out+'/'+$unit+'.exe"');$lines+='if not %errorlevel%==0 exit /b %errorlevel%'
}}
$cinema=if($Revision -ne 'r27'){' /DAC8_CINEMA_SYNC_R28'}else{''};if($Revision -eq 'r29'){$cinema+=' /DAC8_SESSION_POLICY_R29'}
$lines+=('cl /nologo /std:c++17 /EHsc /W4 /WX /O2 /fp:strict /MT /Zi'+$cinema+' /external:I "'+$headers+'" /external:W0 /LD "'+$src+'/steam_coop_bridge.cpp" bcrypt.lib ws2_32.lib dbghelp.lib user32.lib /Fe:"'+$out+'/ac8_steam_coop_'+$Revision+'.dll" /Fo:"'+$out+'/bridge.obj" /link /DEBUG /INCREMENTAL:NO')
$lines+='exit /b %errorlevel%';[IO.File]::WriteAllLines((Join-Path $out 'build.cmd'),$lines,[Text.Encoding]::Default)
Push-Location $out
try{& $env:ComSpec /d /c (Join-Path $out 'build.cmd');if($LASTEXITCODE){throw 'Steam coop build failed'};Get-FileHash (Join-Path $out ('ac8_steam_coop_'+$Revision+'.dll'))}finally{Pop-Location}
