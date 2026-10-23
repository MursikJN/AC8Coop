[CmdletBinding()]
param()
$ErrorActionPreference='Stop';$repo=Split-Path $PSScriptRoot -Parent;$out=Join-Path $repo 'build/lifecycle-lab'
New-Item -ItemType Directory -Path $out -Force|Out-Null
$vswhere=Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$vs=& $vswhere -latest -prerelease -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if(!$vs){throw 'MSVC missing'};$dev=Join-Path $vs 'Common7/Tools/VsDevCmd.bat';$src=Join-Path $repo 'native'
$lines=@('@echo off',('call "'+$dev+'" -no_logo -arch=x64 -host_arch=x64'),'if not %errorlevel%==0 exit /b %errorlevel%')
foreach($unit in @('shared_session_tests','mission_sync_tests','cinema_sync_tests','session_policy_tests')){
 $lines+=('cl /nologo /std:c++17 /EHsc /W4 /WX /O2 /MT "'+$src+'/'+$unit+'.cpp" /Fe:"'+$out+'/'+$unit+'.exe" /Fo:"'+$out+'/'+$unit+'.obj" /link /INCREMENTAL:NO')
 $lines+='if not %errorlevel%==0 exit /b %errorlevel%';$lines+=('"'+$out+'/'+$unit+'.exe"');$lines+='if not %errorlevel%==0 exit /b %errorlevel%'
}
$lines+=('cl /nologo /std:c++17 /EHsc /W4 /WX /O2 /MT /Zi /DAC8_MISSION_SYNC_R26 /DAC8_STEAM_COOP_R27 /DAC8_CINEMA_SYNC_R28 /DAC8_SESSION_POLICY_R29 /DAC8_OWNER_SIM_R30 /LD "'+$src+'/shared_session_local_bridge.cpp" ws2_32.lib /Fe:"'+$out+'/ac8_lifecycle_lab.dll" /Fo:"'+$out+'/bridge.obj" /link /DEBUG /INCREMENTAL:NO')
$lines+='exit /b %errorlevel%';[IO.File]::WriteAllLines((Join-Path $out 'build.cmd'),$lines,[Text.Encoding]::Default)
Push-Location $out
try{& $env:ComSpec /d /c (Join-Path $out 'build.cmd');if($LASTEXITCODE){throw "Mission sync build failed: $LASTEXITCODE"};Get-FileHash (Join-Path $out 'ac8_lifecycle_lab.dll')}finally{Pop-Location}
