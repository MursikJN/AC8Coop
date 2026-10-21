[CmdletBinding()]
param(
 [ValidateSet('host','guest')][string]$Role='host',
 [string]$GameDirectory,
 [switch]$ValidateOnly,
 [ValidateRange(0,5)][int]$RestartBudget=5,
 [ValidatePattern('^$|^[1-9][0-9]{16}$')][string]$ResumeHost=''
)
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$manifest=Get-Content -LiteralPath (Join-Path $root 'lobby-manifest.json') -Raw|ConvertFrom-Json
$revision=$manifest.revision
$diagnostics=$manifest.PSObject.Properties['session_diagnostics'] -and $manifest.session_diagnostics
$automaticReports=$diagnostics -and $manifest.PSObject.Properties['automatic_reports'] -and $manifest.automatic_reports
trap {
 if($diagnostics){
  try{
   $reportRoot=Join-Path $root 'reports';New-Item -ItemType Directory -Force -Path $reportRoot|Out-Null
   [ordered]@{format='ac8-launch-failure-v1';utc=[DateTime]::UtcNow.ToString('o');revision=$revision;role=$Role;error=$_.Exception.Message;stack=$_.ScriptStackTrace}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $reportRoot ('launch-failure-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff')+'.json')) -Encoding UTF8
  }catch{}
 }
 throw
}
if($ResumeHost -and !$manifest.session_policy){throw 'Resume requires the session policy profile.'}
if(!$GameDirectory){
 $candidates=@('D:\Programs\Steam\steamapps\common\ACE COMBAT 8\Game\Binaries\Win64')
 $steamRoot=(Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
 if($steamRoot){
  $libraries=@($steamRoot);$vdf=Join-Path $steamRoot 'steamapps\libraryfolders.vdf'
  if(Test-Path -LiteralPath $vdf){foreach($match in [regex]::Matches([IO.File]::ReadAllText($vdf),'"path"\s+"([^"]+)"')){$libraries+=$match.Groups[1].Value.Replace('\\','\')}}
  foreach($library in $libraries){$candidates+=[IO.Path]::Combine($library,'steamapps\common\ACE COMBAT 8\Game\Binaries\Win64')}
 }
 $GameDirectory=$candidates|Where-Object {Test-Path -LiteralPath ([IO.Path]::Combine($_,'AceCombat8.exe'))}|Select-Object -First 1
}
if(!$GameDirectory){throw 'Game not found. Use -GameDirectory with the Game\Binaries\Win64 directory.'}
$GameDirectory=(Resolve-Path -LiteralPath $GameDirectory).Path
$game=Join-Path $GameDirectory 'AceCombat8.exe'
$steamDll=[IO.Path]::GetFullPath((Join-Path $GameDirectory '..\..\..\Engine\Binaries\ThirdParty\Steamworks\Steamv157\Win64\steam_api64.dll'))
$proxy=Join-Path $GameDirectory 'dwmapi.dll';$proxySource=Join-Path $root 'loader\dwmapi.dll'
foreach($file in $manifest.files){
 $path=[IO.Path]::GetFullPath((Join-Path $root $file.path))
 if(!$path.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Invalid manifest path'}
 if((Get-FileHash -LiteralPath $path).Hash -ne $file.sha256){throw ('Package file mismatch: '+$file.path)}
}
if((Get-FileHash -LiteralPath $game).Hash -ne $manifest.game_sha256){throw 'Game build mismatch; build 25201480 is required.'}
if((Get-FileHash -LiteralPath $steamDll).Hash -ne $manifest.steam_sha256){throw 'Steam runtime mismatch.'}
if($ValidateOnly){Write-Output ($revision+' package, game and Steam runtime verified: '+$root);return}
if($diagnostics){. (Join-Path $root 'Session-Diagnostics.ps1')}
if($automaticReports){. (Join-Path $root 'Auto-Reports.ps1')}
if($manifest.session_policy){. (Join-Path $root 'Session-Policy.ps1')}
if(Get-Process AceCombat8,start_protected_game,EasyAntiCheat_EOS -ErrorAction SilentlyContinue){throw 'Close the previous game normally before starting the new profile.'}
if(Test-Path -LiteralPath $proxy){throw 'An existing loader belongs to another launcher. Let that launcher clean up first.'}
if(!(Get-Process steam -ErrorAction SilentlyContinue)){throw 'Start Steam and sign in first.'}
$stamp=Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$session=Join-Path $root ('evidence\session-'+$stamp+'-'+$Role)
$output=Join-Path $session 'mod';New-Item -ItemType Directory -Path $output -Force|Out-Null
$userDir=if($manifest.session_policy){Get-CoopUserDirectory -Root $root -Session $session -Role $Role}else{Join-Path $root 'userdata'}
$userSaved=Join-Path $userDir 'Saved';New-Item -ItemType Directory -Path $userSaved -Force|Out-Null
$saved=Join-Path $env:LOCALAPPDATA 'BANDAI NAMCO Entertainment\ACE COMBAT 8\Saved'
$backup=Join-Path $root ('save-backups\'+$stamp)
foreach($name in @('SaveGames','Config')){
 $source=Join-Path $saved $name;$target=Join-Path $userSaved $name
 if(Test-Path -LiteralPath $source){
  New-Item -ItemType Directory -Path $backup -Force|Out-Null
  Copy-Item -LiteralPath $source -Destination (Join-Path $backup $name) -Recurse
  if(!(Test-Path -LiteralPath $target)){Copy-Item -LiteralPath $source -Destination $target -Recurse}
 }
}
$record=[ordered]@{format='ac8-steam-lobby-run-v1';revision=$revision;role=$Role;started=(Get-Date -Format o);pid=$null;exit_code=$null;proxy_removed=$false;full_mission_replication=$false;save_policy=$(if($manifest.session_policy){if($Role -eq 'host'){'host-persistent'}else{'guest-discarded'}}else{'legacy'});user_directory=$userDir}
if($diagnostics){
 $record.session_id=[Guid]::NewGuid().ToString('N');$record.started_utc=[DateTime]::UtcNow.ToString('o');$record.diagnostics=$true
 $record.restart_budget=$RestartBudget;$record.resume_requested=[bool]$ResumeHost
 $record.package_manifest_sha256=(Get-FileHash -LiteralPath (Join-Path $root 'lobby-manifest.json')).Hash
 $record.native_sha256=(Get-FileHash -LiteralPath (Join-Path $root $manifest.native_file)).Hash
 $record.game_sha256=$manifest.game_sha256;$record.steam_sha256=$manifest.steam_sha256
 Copy-Item -LiteralPath (Join-Path $root 'lobby-manifest.json') -Destination (Join-Path $session 'package-manifest.json')
 Get-CoopDiagnosticEnvironment|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $session 'environment.json') -Encoding UTF8
}
$recordPath=Join-Path $session 'session.json'
function Save-Record{$record|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $recordPath -Encoding UTF8}
Save-Record
$owned=$false;$process=$null;$autoReportState=$null;$autoReportClock=$null
try{
 [IO.File]::Copy($proxySource,$proxy,$false);$owned=$true
 $info=New-Object Diagnostics.ProcessStartInfo
 $info.FileName=$game;$info.WorkingDirectory=$GameDirectory;$info.UseShellExecute=$false
 $info.Arguments='-SaveToUserDir -UserDir="'+$userDir+'" -windowed -ResX=1280 -ResY=720 --ue4ss-path "'+(Join-Path $root 'runtime\UE4SS.dll')+'"'
 foreach($name in @($info.EnvironmentVariables.Keys)){if($name -like 'AC8_*'){$info.EnvironmentVariables.Remove($name)}}
 $info.EnvironmentVariables['SteamAppId']='2288340'
 $info.EnvironmentVariables['AC8_STEAM_LOBBY']='25201480'
 if($manifest.steam_invites){$info.EnvironmentVariables['AC8_STEAM_INVITES']='25201480'}
 if($manifest.steam_coop){
  if($manifest.session_policy){
   $info.EnvironmentVariables['AC8_SESSION_POLICY']='25201480'
   $info.EnvironmentVariables['AC8_SAVE_POLICY']=$record.save_policy
   if($ResumeHost){$info.EnvironmentVariables['AC8_RESUME_HOST']=$ResumeHost}
  }
  if($manifest.cinema_sync){$info.EnvironmentVariables['AC8_CINEMA_SYNC']='25201480'}
  $info.EnvironmentVariables['AC8_STEAM_COOP']='25201480'
  $info.EnvironmentVariables['AC8_MISSION_SYNC']='25201480'
  $info.EnvironmentVariables['AC8_GUEST_PILOT']='25201480'
  $info.EnvironmentVariables['AC8_LOCAL_SCRIPTS']=Join-Path $root 'runtime\Mods\AC8CoopRecon\Scripts'
  # r19 role module's existing exact-build gate. This main.lua does not expose
  # the development evaluator/mailbox from the older local laboratory.
  $info.EnvironmentVariables['AC8_LOCAL_ADAPTER_DEV']='25201480'
 }
 $info.EnvironmentVariables['AC8_COOP_RECON_OUTPUT']=$output
 $info.EnvironmentVariables['AC8_SHARED_STEAM_DLL']=$steamDll
 $info.EnvironmentVariables['AC8_LOBBY_ROLE']=$Role
 $info.EnvironmentVariables['AC8_LOBBY_SCRIPTS']=Join-Path $root 'runtime\Mods\AC8CoopRecon\Scripts'
 $info.EnvironmentVariables['AC8_LOBBY_DLL']=Join-Path $root $manifest.native_file
 if($diagnostics){
  $info.EnvironmentVariables['AC8_SESSION_DIAGNOSTICS']='1'
  $info.EnvironmentVariables['AC8_SESSION_ID']=$record.session_id
  $info.EnvironmentVariables['AC8_PACKAGE_REVISION']=$revision
 }
 $process=[Diagnostics.Process]::Start($info);$record.pid=$process.Id;Save-Record
 if($automaticReports){
  try{$autoReportClock=[Diagnostics.Stopwatch]::StartNew();$autoReportState=New-CoopAutoReportState -Root $root -Session $session -UserSaved $userSaved -FallbackSaved $saved -NowMs 0;$record.automatic_reports=$true;Save-Record}catch{$record.auto_report_error=$_.Exception.Message;Save-Record}
 }
 Write-Output ($revision+' '+$Role+' PID '+$process.Id+'. Logs: '+$session)
 # Keep loader ownership until this game exits normally, including after Codex yields.
 while(!$process.HasExited){
  if($autoReportState){try{Update-CoopAutoReports -State $autoReportState -NowMs $autoReportClock.ElapsedMilliseconds}catch{Write-Warning ('Automatic report observer: '+$_.Exception.Message)}}
  Start-Sleep -Seconds 1
 }
 $record.exit_code=$process.ExitCode
}catch{$record.error=$_.Exception.Message;throw}
finally{
 if($process -and !$process.HasExited){while(!$process.HasExited){Start-Sleep -Seconds 1}}
 if($process){$record.exit_code=$process.ExitCode}
 $cleanupDeadline=[DateTime]::UtcNow.AddSeconds(5)
 while($owned -and (Get-Process AceCombat8 -ErrorAction SilentlyContinue) -and [DateTime]::UtcNow -lt $cleanupDeadline){Start-Sleep -Milliseconds 100}
 if($owned -and !(Get-Process AceCombat8 -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath $proxy)){
  if((Get-FileHash -LiteralPath $proxy).Hash -eq $manifest.proxy_sha256){Remove-Item -LiteralPath $proxy;$record.proxy_removed=$true}
 }
 foreach($log in @((Join-Path $root 'runtime\UE4SS.log'))){if(Test-Path -LiteralPath $log){Copy-Item -LiteralPath $log -Destination $output}}
 $gameLogs=Join-Path $userSaved 'Logs'
 if(Test-Path -LiteralPath $gameLogs){Get-ChildItem -LiteralPath $gameLogs -File -Filter '*.log'|Where-Object {$_.Length -lt 64MB -and $_.LastWriteTime -ge [DateTime]::Parse($record.started)}|ForEach-Object {Copy-Item -LiteralPath $_.FullName -Destination $output}}
 $record.finished=Get-Date -Format o;Save-Record
 if($diagnostics){try{Copy-CoopDiagnosticLogs -UserSaved $userSaved -Output $output -Since ([DateTime]::Parse($record.started)) -RuntimeLog (Join-Path $root 'runtime/UE4SS.log') -FallbackSaved $saved}catch{Write-Warning ('Diagnostic game log copy failed: '+$_.Exception.Message)}}
 try{& (Join-Path $root 'Collect-CoopLogs.ps1') -SessionDirectory $session -ReportsDirectory (Join-Path $root 'reports')}catch{Write-Warning ('Report collection failed: '+$_.Exception.Message)}
}
if($manifest.session_policy -and $process -and $process.HasExited -and $record.proxy_removed -and $RestartBudget -gt 0){
 try{$plan=Get-CoopRestartPlan -Root $root -Session $session -Role $Role -ExitCode $process.ExitCode}catch{$plan=$null;$record.restart_rejected=$_.Exception.Message;Save-Record;if($diagnostics){try{& (Join-Path $root 'Collect-CoopLogs.ps1') -SessionDirectory $session -ReportsDirectory (Join-Path $root 'reports')}catch{Write-Warning ('Restart failure report: '+$_.Exception.Message)}}}
 if($plan){
  $record.shared_restart=$plan.RestartId;Save-Record
  if($diagnostics){try{& (Join-Path $root 'Collect-CoopLogs.ps1') -SessionDirectory $session -ReportsDirectory (Join-Path $root 'reports')}catch{Write-Warning ('Restart decision report: '+$_.Exception.Message)}}
  # A fresh process is the supported lifecycle boundary for the pinned r19 DLL.
  # The new game returns to a lobby and still needs normal title/profile input.
  & $PSCommandPath -Role $Role -GameDirectory $GameDirectory -RestartBudget ($RestartBudget-1) -ResumeHost $plan.HostId
 }
}
