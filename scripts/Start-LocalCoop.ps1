[CmdletBinding()]
param(
 [string]$GameDirectory='D:\Programs\Steam\steamapps\common\ACE COMBAT 8\Game\Binaries\Win64',
 [switch]$ValidateOnly,
 [switch]$GuestSimulator,
 [switch]$HangarAdapter,
 [switch]$AdapterDevelopment,
 [switch]$SceneViewer,
 [switch]$MissionSync,
 [int]$Width=960,[int]$Height=540
)
$ErrorActionPreference='Stop'
if($SceneViewer -and (!$GuestSimulator -or !$HangarAdapter)){throw 'SceneViewer requires GuestSimulator and HangarAdapter'}
if($MissionSync -and (!$GuestSimulator -or !$HangarAdapter)){throw 'MissionSync requires GuestSimulator and HangarAdapter'}
$repo=Split-Path $PSScriptRoot -Parent
$revision=if($MissionSync){'r26'}elseif($HangarAdapter){'r13'}else{'r12'}
$profile=Join-Path $repo ('profiles\ac8-local-'+$revision)
$manifest=Get-Content -LiteralPath (Join-Path $profile 'local-manifest.json') -Raw|ConvertFrom-Json
$game=Join-Path $GameDirectory 'AceCombat8.exe'
$proxy=Join-Path $GameDirectory 'dwmapi.dll'
$proxySource=Join-Path $repo 'packages\ue4ss-3.0.1-1181-g83330635\dwmapi.dll'
if($Width -lt 800 -or $Width -gt 1920 -or $Height -lt 450 -or $Height -gt 1080){throw 'Window size out of supported development range'}
if((Get-FileHash -LiteralPath $game).Hash -ne $manifest.game_sha256){throw 'Game hash mismatch'}
if((Get-FileHash -LiteralPath $proxySource).Hash -ne $manifest.proxy_sha256){throw 'Proxy hash mismatch'}
foreach($file in $manifest.files){
 $path=[IO.Path]::GetFullPath((Join-Path $profile $file.path))
 if(!$path.StartsWith($profile+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Invalid manifest path'}
 if((Get-FileHash -LiteralPath $path).Hash -ne $file.sha256){throw ('Profile file mismatch: '+$file.path)}
}
if(Test-Path -LiteralPath $proxy){throw 'An existing game proxy must be cleaned up by its owning launcher first'}
if(Get-Process AceCombat8,start_protected_game,EasyAntiCheat_EOS -ErrorAction SilentlyContinue){throw 'Close the game before starting a local pair'}
if(!(Get-Process steam -ErrorAction SilentlyContinue)){throw 'Start Steam first'}
$panel=Join-Path $repo 'coop\guest_simulator.py'
$python=Join-Path $repo '.venv\Scripts\pythonw.exe'
if($GuestSimulator -and (!(Test-Path -LiteralPath $panel)-or !(Test-Path -LiteralPath $python))){throw 'Guest panel or Python runtime missing'}
if($ValidateOnly){Write-Output 'Both local profiles and game/proxy hashes verified; no game edits';return}
$session=Join-Path $profile ('evidence\pair-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $session -Force|Out-Null
Copy-Item -LiteralPath (Join-Path $profile 'local-manifest.json') -Destination (Join-Path $session 'launch-manifest.json')
$record=[ordered]@{started=(Get-Date -Format o);transport='tcp-loopback';guest_kind=$(if($GuestSimulator){'panel'}else{'game'});game_adapter_ready=$false;host_pid=$null;guest_pid=$null;host_exit=$null;guest_exit=$null;proxy_removed=$false;arguments=@{}}
$recordPath=Join-Path $session 'pair.json'
function Save-Record{$record|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $recordPath -Encoding UTF8}
$bytes=New-Object byte[] 8;$rng=[Security.Cryptography.RandomNumberGenerator]::Create()
try{$rng.GetBytes($bytes)}finally{$rng.Dispose()}
$token=([BitConverter]::ToUInt64($bytes,0) -band 0x1FFFFFFFFFFFFF).ToString();if($token -eq '0'){$token='1'}
# Preserve original saves/config as an immutable per-run backup before testing UserDir isolation.
$saved=Join-Path $env:LOCALAPPDATA 'BANDAI NAMCO Entertainment\ACE COMBAT 8\Saved'
foreach($name in @('SaveGames','Config')){
 $source=Join-Path $saved $name
 if(Test-Path -LiteralPath $source){Copy-Item -LiteralPath $source -Destination (Join-Path $session ('original-'+$name)) -Recurse}
}
$owned=$false;$processes=@();$launchComplete=$false
function Start-Instance([string]$role,[int]$port){
 $roleRoot=Join-Path $profile $role;$output=Join-Path $session $role
 New-Item -ItemType Directory -Path $output -Force|Out-Null
 $userDir=Join-Path $roleRoot 'userdata'
 # Clone only to new destinations; do not overwrite a previous local test profile.
 $userSaved=Join-Path $userDir 'Saved';New-Item -ItemType Directory -Path $userSaved -Force|Out-Null
 foreach($name in @('SaveGames','Config')){
  $source=Join-Path $saved $name;$target=Join-Path $userSaved $name
  if((Test-Path -LiteralPath $source)-and !(Test-Path -LiteralPath $target)){Copy-Item -LiteralPath $source -Destination $target -Recurse}
 }
 $info=New-Object Diagnostics.ProcessStartInfo
 $info.FileName=$game;$info.WorkingDirectory=$GameDirectory;$info.UseShellExecute=$false
 $x=if($role -eq 'host'){20}else{40+$Width}
 $info.Arguments='-SaveToUserDir -UserDir="'+$userDir+'" -windowed -ResX='+$Width+' -ResY='+$Height+' -WinX='+$x+' -WinY=50 --ue4ss-path "'+(Join-Path $roleRoot 'runtime\UE4SS.dll')+'"'
 foreach($name in @($info.EnvironmentVariables.Keys)){if($name -like 'AC8_*'){$info.EnvironmentVariables.Remove($name)}}
 $info.EnvironmentVariables['SteamAppId']='2288340'
 $info.EnvironmentVariables['AC8_LOCAL_SESSION']='25201480'
 $info.EnvironmentVariables['AC8_LOCAL_ROLE']=$role
 $info.EnvironmentVariables['AC8_LOCAL_PORT']="$port"
 $info.EnvironmentVariables['AC8_LOCAL_TOKEN']=$token
 $info.EnvironmentVariables['AC8_COOP_RECON_OUTPUT']=$output
 $info.EnvironmentVariables['AC8_LOCAL_SCRIPTS']=Join-Path $roleRoot 'runtime\Mods\AC8CoopRecon\Scripts'
 $info.EnvironmentVariables['AC8_LOCAL_DLL']=Join-Path $roleRoot ('runtime\ac8_local_session_'+$revision+'.dll')
 if($MissionSync){$info.EnvironmentVariables['AC8_MISSION_SYNC']='25201480'}
 if($HangarAdapter){
  $info.EnvironmentVariables['AC8_LOCAL_HANGAR']='25201480'
  $info.EnvironmentVariables['AC8_COOP_RECON']='1'
  $info.EnvironmentVariables['AC8_COOP_RECON_EXTENSION']=Join-Path $roleRoot 'runtime\Mods\AC8CoopRecon\Scripts\main.lua'
  $info.EnvironmentVariables['AC8_COOP_MENU_ROUTE_DLL']=Join-Path $roleRoot 'runtime\ac8_menu_route_r13.dll'
  $info.EnvironmentVariables['AC8_COOP_LOBBY']='25201480'
 }
 if($AdapterDevelopment){$info.EnvironmentVariables['AC8_LOCAL_ADAPTER_DEV']='25201480'}
 if($SceneViewer){$info.EnvironmentVariables['AC8_SCENE_VIEWER']='25201480'}
 $record.arguments[$role]=$info.Arguments
 $process=[Diagnostics.Process]::Start($info)
 $record[$role+'_pid']=$process.Id;Save-Record
 return $process
}
try{
 [IO.File]::Copy($proxySource,$proxy,$false);$owned=$true
 $hostProcess=Start-Instance 'host' 0;$processes+=,$hostProcess
 $deadline=[DateTime]::UtcNow.AddSeconds(120);$port=0
 $statusPath=Join-Path $session 'host\shared-session-status.tsv'
 while(!$port){
  if($hostProcess.HasExited){throw ('Host exited before transport startup: '+$hostProcess.ExitCode)}
  if([DateTime]::UtcNow -gt $deadline){throw 'Host mod did not publish a port within 120 seconds'}
  if(Test-Path -LiteralPath $statusPath){
   $status=[IO.File]::ReadAllText($statusPath)
   if($status -match '(?m)^port\t([0-9]+)\r?$'){$port=[int]$Matches[1]}
   if($status -match '(?m)^transport\terror\r?$'){throw 'Host transport initialization failed'}
  }
  Start-Sleep -Milliseconds 250
 }
 if($GuestSimulator){
  $guestOutput=Join-Path $session 'guest';New-Item -ItemType Directory -Path $guestOutput -Force|Out-Null
  $guestDll=Join-Path $profile ('guest\runtime\ac8_local_session_'+$revision+'.dll')
  $descriptor=[ordered]@{format='ac8-guest-simulator-v1';hangar_adapter=[bool]$HangarAdapter;scene_viewer=[bool]$SceneViewer;mission_sync=[bool]$MissionSync;address='127.0.0.1';port=$port;token=$token;host_pid=$hostProcess.Id;host_output=(Join-Path $session 'host');guest_output=$guestOutput;guest_dll=$guestDll;guest_dll_sha256=(Get-FileHash -LiteralPath $guestDll).Hash}
  $descriptorPath=Join-Path $session 'simulator-session.json'
  $descriptor|ConvertTo-Json|Set-Content -LiteralPath $descriptorPath -Encoding UTF8
  $guestProcess=Start-Process -FilePath $python -ArgumentList @(('"'+$panel+'"'),'--session',('"'+$descriptorPath+'"')) -WindowStyle Hidden -PassThru
  $record.guest_pid=$guestProcess.Id;Save-Record
 }else{$guestProcess=Start-Instance 'guest' $port}
 $processes+=,$guestProcess
 $launchComplete=$true
 Write-Output ('Local pair launched. Host PID '+$hostProcess.Id+', guest PID '+$guestProcess.Id+'. Reports: '+$session)
 # The loader belongs to this launcher until BOTH processes terminate.
 while(@($processes|Where-Object {!$_.HasExited}).Count -gt 0){
  if($GuestSimulator -and $hostProcess.HasExited -and !$guestProcess.HasExited){[IO.File]::WriteAllText((Join-Path $guestOutput 'close-panel'),'host exited')}
  Save-Record;Start-Sleep -Seconds 1
 }
}catch{
 $record.error=$_.Exception.Message;Save-Record;Write-Warning $record.error
 # If only the host started, retain loader ownership while that process is alive too.
 while(@($processes|Where-Object {!$_.HasExited}).Count -gt 0){Start-Sleep -Seconds 1}
 throw
}finally{
 foreach($process in $processes){$process.Refresh()}
 if($record.host_pid){$record.host_exit=$processes[0].ExitCode}
 if($launchComplete){$record.guest_exit=$processes[1].ExitCode}
 $cleanupDeadline=[DateTime]::UtcNow.AddSeconds(5)
 while($owned -and (Get-Process AceCombat8 -ErrorAction SilentlyContinue) -and [DateTime]::UtcNow -lt $cleanupDeadline){Start-Sleep -Milliseconds 100}
 if($owned -and !(Get-Process AceCombat8 -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath $proxy)){
  if((Get-FileHash -LiteralPath $proxy).Hash -eq $manifest.proxy_sha256){Remove-Item -LiteralPath $proxy;$record.proxy_removed=$true}
 }
 $record.finished=(Get-Date -Format o);Save-Record
}
