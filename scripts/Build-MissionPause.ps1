param([switch]$Check,[switch]$DisconnectLab)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent;$out=Join-Path $repo 'build/mission-pause-r26'
if($DisconnectLab){$out=Join-Path $repo 'build/lifecycle-disconnect-pause'}
New-Item -ItemType Directory -Path $out -Force|Out-Null
$vswhere=Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$vs=& $vswhere -latest -prerelease -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if(!$vs){throw 'MSVC missing'};$dev=Join-Path $vs 'Common7/Tools/VsDevCmd.bat'
$lines=@('@echo off',('call "'+$dev+'" -no_logo -arch=x64 -host_arch=x64'),'if not %errorlevel%==0 exit /b %errorlevel%')
if($Check){$lines+=@(('cl /nologo /std:c++17 /EHsc /W4 /WX /O2 /MT "'+$repo+'/native/mission_pause_lease_tests.cpp" /Fe:"'+$out+'/pause_lease_tests.exe" /Fo:"'+$out+'/lease.obj"'),'if not %errorlevel%==0 exit /b %errorlevel%',('"'+$out+'/pause_lease_tests.exe"'),'if not %errorlevel%==0 exit /b %errorlevel%')}
if($Check){$lines+=@(('cl /nologo /std:c++17 /EHsc /W4 /WX /O2 /MT "'+$repo+'/native/adapter_bootstrap_contract_tests.cpp" /Fe:"'+$out+'/adapter_bootstrap_contract_tests.exe" /Fo:"'+$out+'/bootstrap-tests.obj"'),'if not %errorlevel%==0 exit /b %errorlevel%',('"'+$out+'/adapter_bootstrap_contract_tests.exe"'),'if not %errorlevel%==0 exit /b %errorlevel%')}
$define=if($DisconnectLab){'/DAC8_DISCONNECT_PAUSE '}else{''}
$lines+=@(('cl /nologo /std:c++17 /EHsc /W4 /WX /O2 /MT /LD '+$define+'"'+$repo+'/native/mission_sync_pause.cpp" /Fe:"'+$out+'/ac8_mission_pause_r26.dll" /Fo:"'+$out+'/pause.obj" /link /INCREMENTAL:NO'),'exit /b %errorlevel%')
[IO.File]::WriteAllLines((Join-Path $out 'build.cmd'),$lines,[Text.Encoding]::Default)
Push-Location $out
try{& $env:ComSpec /d /c (Join-Path $out 'build.cmd');if($LASTEXITCODE){throw 'Mission pause build failed'};Get-FileHash (Join-Path $out 'ac8_mission_pause_r26.dll')}finally{Pop-Location}
