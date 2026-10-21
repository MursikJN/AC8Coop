[CmdletBinding()]
param([string]$OutputRoot='',[ValidatePattern('^r20[a-z]?$')][string]$Revision='r20',[switch]$TestsOnly)
$ErrorActionPreference='Stop';$repo=Split-Path $PSScriptRoot -Parent
if(!$OutputRoot){$OutputRoot=Join-Path $repo ('build\guest-pilot-'+$Revision)}
New-Item -ItemType Directory -Force -Path $OutputRoot|Out-Null;$OutputRoot=(Resolve-Path $OutputRoot).Path
$vswhere=Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vs=& $vswhere -latest -prerelease -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if(!$vs){throw 'MSVC missing'};$dev=Join-Path $vs 'Common7\Tools\VsDevCmd.bat';$src=Join-Path $repo 'native';$headers=Join-Path $repo 'packages\valve-headers-d534'
$lines=@('@echo off',('call "'+$dev+'" -no_logo -arch=x64 -host_arch=x64'),'if not %errorlevel%==0 exit /b %errorlevel%')
foreach($unit in @('guest_pilot_tests','guest_pilot_transport_tests')){
 $lines+=('cl /nologo /std:c++17 /EHsc /W4 /WX /O2 /fp:strict /MT /external:I "'+$headers+'" /external:W0 "'+$src+'\'+$unit+'.cpp" bcrypt.lib /Fe:"'+$OutputRoot+'\'+$unit+'.exe" /Fo:"'+$OutputRoot+'\'+$unit+'.obj" /link /INCREMENTAL:NO')
 $lines+='if not %errorlevel%==0 exit /b %errorlevel%';$lines+=('"'+$OutputRoot+'\'+$unit+'.exe"');$lines+='if not %errorlevel%==0 exit /b %errorlevel%'
}
if(!$TestsOnly){
 $lines+=('cl /nologo /std:c++17 /EHsc /W4 /WX /O2 /fp:strict /MT /Zi /external:I "'+$headers+'" /external:W0 /LD /DAC8_PILOT_REV='+$Revision+' "'+$src+'\guest_pilot_bridge.cpp" bcrypt.lib ws2_32.lib dbghelp.lib user32.lib /Fe:"'+$OutputRoot+'\ac8_guest_pilot_'+$Revision+'.dll" /Fo:"'+$OutputRoot+'\pilot.obj" /link /DEBUG /INCREMENTAL:NO')
}
$lines+='exit /b %errorlevel%'
[IO.File]::WriteAllLines((Join-Path $OutputRoot 'build.cmd'),$lines,[Text.Encoding]::Default)
Push-Location $OutputRoot
try{& $env:ComSpec /d /c (Join-Path $OutputRoot 'build.cmd');if($LASTEXITCODE){throw "Guest pilot build failed: $LASTEXITCODE"};if(!$TestsOnly){Get-FileHash (Join-Path $OutputRoot ('ac8_guest_pilot_'+$Revision+'.dll'))}}finally{Pop-Location}
