$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent;$out=Join-Path $repo 'build/cinema-sync-r26'
New-Item -ItemType Directory -Path $out -Force|Out-Null
$vswhere=Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$vs=& $vswhere -latest -prerelease -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if(!$vs){throw 'MSVC missing'};$dev=Join-Path $vs 'Common7/Tools/VsDevCmd.bat'
$lines=@('@echo off',('call "'+$dev+'" -no_logo -arch=x64 -host_arch=x64'),'if not %errorlevel%==0 exit /b %errorlevel%',('cl /nologo /std:c++17 /EHsc /W4 /WX /O2 /MT "'+$repo+'/native/cinema_vote_gate_tests.cpp" /Fe:"'+$out+'/cinema_vote_gate_tests.exe" /Fo:"'+$out+'/gate.obj"'),'if not %errorlevel%==0 exit /b %errorlevel%',('"'+$out+'/cinema_vote_gate_tests.exe"'),'if not %errorlevel%==0 exit /b %errorlevel%',('cl /nologo /std:c++17 /EHsc /W4 /WX /O2 /MT /LD "'+$repo+'/native/cinema_sync_guard.cpp" /Fe:"'+$out+'/ac8_cinema_guard_r26_3.dll" /Fo:"'+$out+'/guard.obj" /link /INCREMENTAL:NO'),'exit /b %errorlevel%')
[IO.File]::WriteAllLines((Join-Path $out 'build.cmd'),$lines,[Text.Encoding]::Default)
Push-Location $out
try{& $env:ComSpec /d /c (Join-Path $out 'build.cmd');if($LASTEXITCODE){throw 'Cinema guard build failed'};Get-FileHash (Join-Path $out 'ac8_cinema_guard_r26_3.dll')}finally{Pop-Location}
