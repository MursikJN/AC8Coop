[CmdletBinding()]
param([string]$BuildRoot='', [string]$OutputRoot='')
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
if(!$BuildRoot){$BuildRoot=Join-Path $repo 'build\shared-session-r12'}
$exe=Join-Path $BuildRoot 'shared_session_local_trial.exe'
if(!(Test-Path -LiteralPath $exe)){throw 'Build first with scripts/Build-SharedSession.ps1'}
if(!$OutputRoot){$OutputRoot=Join-Path $repo ('build\local-session-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff'))}
New-Item -ItemType Directory -Path $OutputRoot -Force|Out-Null
$OutputRoot=(Resolve-Path $OutputRoot).Path
# Fresh nonzero token, separate from any Steam identity. Loopback is development only.
$bytes=New-Object byte[] 8
$rng=[Security.Cryptography.RandomNumberGenerator]::Create()
try{$rng.GetBytes($bytes)}finally{$rng.Dispose()}
$token=([BitConverter]::ToUInt64($bytes,0) -band [long]::MaxValue).ToString()
if($token -eq '0'){$token='1'}
$hostPrefix=Join-Path $OutputRoot 'host';$guestPrefix=Join-Path $OutputRoot 'guest'
$hostProcess=$null;$guestProcess=$null
try{
 $hostProcess=Start-Process -FilePath $exe -ArgumentList @('host','0',$token,('"'+$hostPrefix+'"')) -WindowStyle Hidden -PassThru
 $deadline=[DateTime]::UtcNow.AddSeconds(5)
 while(!(Test-Path -LiteralPath ($hostPrefix+'.port'))){
  if($hostProcess.HasExited -or [DateTime]::UtcNow -gt $deadline){throw 'Local host did not start; inspect host.log'}
  Start-Sleep -Milliseconds 20
 }
 $port=[int][IO.File]::ReadAllText($hostPrefix+'.port')
 $guestProcess=Start-Process -FilePath $exe -ArgumentList @('guest',"$port",$token,('"'+$guestPrefix+'"')) -WindowStyle Hidden -PassThru
 foreach($process in @($guestProcess,$hostProcess)){
  if(!$process.WaitForExit(15000)){throw 'Local test timed out'}
  $process.Refresh();if($process.ExitCode -ne 0){throw ('Local test failed: exit '+$process.ExitCode+'; inspect '+$OutputRoot)}
 }
 $result=[ordered]@{result='passed';transport='tcp-loopback';address='127.0.0.1';port=$port;processes=2;host_pid=$hostProcess.Id;guest_pid=$guestProcess.Id;host_authority=$true;guest_selection_rejected=$true;readiness_reset=$true;gameplay_tested=$false;two_game_instances_tested=$false}
 $result|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $OutputRoot 'result.json') -Encoding UTF8
 $result|ConvertTo-Json
}finally{
 foreach($process in @($guestProcess,$hostProcess)){if($null -ne $process -and !$process.HasExited){Stop-Process -Id $process.Id -ErrorAction SilentlyContinue}}
}
