[CmdletBinding()]
param([switch]$Launch,[switch]$SteamOfflineConfirmed,[switch]$HeadlessGuest,[switch]$StopOnDisconnect,[string]$ProfileRoot,[string]$UserDataSeed,[string]$OutputRoot,[string]$KitRoot)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$profile=Join-Path $repo 'profiles/ac8-lifecycle-pair-v1'
if($StopOnDisconnect){$profile=Join-Path $repo 'profiles/ac8-lifecycle-stop-v4'}
if($ProfileRoot){$profile=[IO.Path]::GetFullPath($ProfileRoot)}
$kit=Join-Path $repo 'ac8-steam-coop-r31-compact'
if($KitRoot){$kit=[IO.Path]::GetFullPath($KitRoot)}
. (Join-Path $PSScriptRoot 'Coop-Kit.ps1')
foreach($f in (Get-Content "$profile/profile-manifest.json" -Raw|ConvertFrom-Json)){
 $p=Join-Path $profile $f.path; Assert-CoopPlainPath $p
 if((Get-FileHash -LiteralPath $p).Hash -ne $f.sha256){throw "Profile hash mismatch: $($f.path)"}
}
$cfg=Get-Content "$kit/lobby-manifest.json" -Raw|ConvertFrom-Json
if($StopOnDisconnect){
 if(!$HeadlessGuest){throw 'Stop lab currently requires one game and headless guest'}
 foreach($f in @('runtime/ac8_mission_pause_r26.dll','runtime/Mods/LifecycleLab/Scripts/disconnect_stop.lua','runtime/Mods/LifecycleLab/Scripts/mission_sync_pause.lua')){
  if(!(Test-Path (Join-Path $profile $f))){throw "Missing stop profile file: $f"}
 }
}
$guard=$null;$owned=$false;$processes=@();$record=$null;$session=$null
try{
 $dir=Test-CoopLab -Root $kit -Manifest $cfg -ArchiveGuard ([ref]$guard)
 $proxy=Join-Path $dir 'dwmapi.dll'
 $loader=Join-Path $repo 'packages/ue4ss-3.0.1-1181-g83330635/dwmapi.dll'
 if((Get-FileHash $loader).Hash -ne '93B9431A5A4F32C675D269C5DA1C9B3EC6F88552EC20C282AB435F411E9271FB'){throw 'Loader hash'}
 if(Test-Path $proxy){throw 'Existing loader belongs to another launcher'}
 if(!$Launch){Write-Output 'Lifecycle pair preflight PASS; no game launched';return}
 if(!$SteamOfflineConfirmed){throw 'Steam offline confirmation required'}
 if(Get-Process AceCombat8,start_protected_game,EasyAntiCheat_EOS -ErrorAction SilentlyContinue){throw 'Close game first'}
 $private=Join-Path $repo 'evidence/lifecycle-lab'
 if($OutputRoot){$private=[IO.Path]::GetFullPath($OutputRoot)}
 $session=Join-Path $private ('pair-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss'))
 New-Item -ItemType Directory -Path $session -Force|Out-Null
 Copy-Item "$profile/profile-manifest.json" "$session/profile-manifest.json"
 [IO.File]::WriteAllText((Join-Path $profile 'latest-session.txt'),$session)
 $bytes=New-Object byte[] 8;$rng=[Security.Cryptography.RandomNumberGenerator]::Create()
 try{$rng.GetBytes($bytes)}finally{$rng.Dispose()}
 $token=([BitConverter]::ToUInt64($bytes,0) -band 0x1FFFFFFFFFFFFF).ToString();if($token -eq '0'){$token='1'}
 $record=[ordered]@{format='ac8-lifecycle-pair-v1';started_utc=[DateTime]::UtcNow.ToString('o');host_pid=$null;guest_pid=$null;host_exit=$null;guest_exit=$null;proxy_removed=$false;originals_written=$false;transport='loopback';game_adapter='read-only-observation';game=$dir;error=$null}
 if($StopOnDisconnect){$record.game_adapter='flight-peer-loss-stock-pause-v1'}
 function Save-Record{$record|ConvertTo-Json|Set-Content -LiteralPath "$session/pair.json" -Encoding UTF8}
 function Start-Role([string]$role,[string]$port){
  $out=Join-Path $session $role;New-Item -ItemType Directory -Path $out|Out-Null
  Copy-Item "$profile/runtime" "$out/runtime" -Recurse
  $saved=Join-Path $out 'userdata/Saved';New-Item -ItemType Directory -Path $saved -Force|Out-Null
  $original=Join-Path $env:LOCALAPPDATA 'BANDAI NAMCO Entertainment/ACE COMBAT 8/Saved'
  if($UserDataSeed){$original=Join-Path ([IO.Path]::GetFullPath($UserDataSeed)) 'Saved'}
  # The game restores graphics from System.sav over the INI during profile load.
  # Seed the guest from the host's isolated, already saved menu settings.
  # Both roles still receive independent files; no hard links or shared saves.
  if($role -eq 'guest'){$original=Join-Path $session 'host/userdata/Saved'}
  $record[($role+'_userdata_source')]=$original
  foreach($name in @('SaveGames','Config')){
   $src=Join-Path $original $name
   if(Test-Path $src){
    Assert-CoopPlainPath $src
    if(Get-ChildItem -LiteralPath $src -Recurse -Force|Where-Object {$_.Attributes -band [IO.FileAttributes]::ReparsePoint}){throw 'Linked save source'}
    Copy-Item -LiteralPath $src -Destination (Join-Path $saved $name) -Recurse
   }
  }
  $ini=Join-Path $saved 'Config/Windows/GameUserSettings.ini'
  $settings=[IO.File]::ReadAllText($ini)
  $settings=[regex]::Replace($settings,'(?m)^(sg\.[A-Za-z]+Quality)=.*$','$1=0')
  $overrides=@{ResolutionSizeX='960';ResolutionSizeY='540';LastUserConfirmedResolutionSizeX='960';LastUserConfirmedResolutionSizeY='540';FullscreenMode='2';LastConfirmedFullscreenMode='2';PreferredFullscreenMode='2';FrameRateLimit='30.000000'}
  foreach($key in $overrides.Keys){$settings=[regex]::Replace($settings,'(?m)^'+$key+'=.*$',$key+'='+$overrides[$key])}
  [IO.File]::WriteAllText($ini,$settings)
  $info=New-Object Diagnostics.ProcessStartInfo
  $info.FileName=Join-Path $dir 'AceCombat8.exe';$info.WorkingDirectory=$dir;$info.UseShellExecute=$false
  $info.Arguments='-SaveToUserDir -UserDir="'+(Join-Path $out 'userdata')+'" -windowed -ResX=960 -ResY=540 --ue4ss-path "'+(Join-Path $out 'runtime/UE4SS.dll')+'"'
  foreach($key in @($info.EnvironmentVariables.Keys)){if($key -like 'AC8_*'){$info.EnvironmentVariables.Remove($key)}}
  $info.EnvironmentVariables['SteamAppId']='2288340'
  foreach($key in @('AC8_LIFECYCLE_LAB','AC8_LOCAL_SESSION','AC8_MISSION_SYNC','AC8_LOCAL_HANGAR')){$info.EnvironmentVariables[$key]='25201480'}
  $info.EnvironmentVariables['AC8_LOCAL_ROLE']=$role;$info.EnvironmentVariables['AC8_LOCAL_PORT']=$port
  $info.EnvironmentVariables['AC8_LOCAL_TOKEN']=$token;$info.EnvironmentVariables['AC8_COOP_RECON_OUTPUT']=$out
  $info.EnvironmentVariables['AC8_LOCAL_DLL']=Join-Path $out 'runtime/ac8_lifecycle_lab.dll'
  if($StopOnDisconnect){
   $info.EnvironmentVariables['AC8_LIFECYCLE_STOP']='25201480'
   $info.EnvironmentVariables['AC8_LIFECYCLE_SCRIPTS']=Join-Path $out 'runtime/Mods/LifecycleLab/Scripts'
  }
  return [Diagnostics.Process]::Start($info)
 }
 [IO.File]::Copy($loader,$proxy,$false);$owned=$true
 $hostGame=Start-Role 'host' '0';$processes+=,$hostGame;$record.host_pid=$hostGame.Id;Save-Record
 Write-Output ("Host PID "+$hostGame.Id+"; session "+$session)
 # Explicit observation gate: only after the host finishes shader compilation and reaches menu.
 while(!$HeadlessGuest -and !(Test-Path "$session/start-guest")){
  if($hostGame.HasExited){throw 'Host exited before guest gate'};if(Test-Path "$session/cancel"){throw 'Pair cancelled before guest launch'}
  Start-Sleep -Milliseconds 300
 }
 if(!$HeadlessGuest){
  $text=Get-Content "$session/start-guest" -Raw
  if($text.Trim() -ne 'main_menu_observed'){throw 'Invalid guest launch gate'}
 }
 $portWait=[DateTime]::UtcNow.AddSeconds(120)
 while(!(Test-Path "$session/host/shared-session-status.tsv")){
  if($hostGame.HasExited -or [DateTime]::UtcNow -gt $portWait){throw 'Host bridge did not start'}
  Start-Sleep -Milliseconds 300
 }
 $status=Get-Content "$session/host/shared-session-status.tsv" -Raw
 if($status -notmatch '(?m)^port\t(\d+)\r?$'){throw 'Host port unavailable'}
 if($HeadlessGuest){
  $out=Join-Path $session 'guest';New-Item -ItemType Directory -Path $out|Out-Null
  $info=New-Object Diagnostics.ProcessStartInfo
  $info.FileName=Join-Path $repo '.venv/Scripts/python.exe';$info.WorkingDirectory=$repo;$info.UseShellExecute=$false;$info.CreateNoWindow=$true
  $info.Arguments='"'+(Join-Path $repo 'coop/lifecycle_lab.py')+'" worker guest "'+$out+'" '+$token+' '+$Matches[1]+' "'+(Join-Path $profile 'runtime/ac8_lifecycle_lab.dll')+'"'
  $guestGame=[Diagnostics.Process]::Start($info);$record.guest_kind='headless_native_bridge'
 }else{$guestGame=Start-Role 'guest' $Matches[1];$record.guest_kind='game'}
 $processes+=,$guestGame;$record.guest_pid=$guestGame.Id;Save-Record
 Write-Output ("Guest PID "+$guestGame.Id)
 $hostGame.WaitForExit()
 if($HeadlessGuest){[IO.File]::WriteAllText("$session/guest/stop",'host_exited')}
 $guestGame.WaitForExit()
 $record.host_exit=$hostGame.ExitCode;$record.guest_exit=$guestGame.ExitCode
}catch{if($record){$record.error=$_.Exception.Message};throw}
finally{
 if($HeadlessGuest -and $session -and (Test-Path "$session/guest")){[IO.File]::WriteAllText("$session/guest/stop",'launcher_cleanup')}
 foreach($p in $processes){if(!$p.HasExited){$p.WaitForExit()}}
 if($record -and $hostGame -and $hostGame.HasExited){$record.host_exit=$hostGame.ExitCode}
 if($record -and $guestGame -and $guestGame.HasExited){$record.guest_exit=$guestGame.ExitCode}
 if($record){
  $record.outcome=if($record.error){'launcher_error'}elseif($null -eq $record.guest_exit){'guest_not_completed'}elseif($record.host_exit -ne 0 -or $record.guest_exit -ne 0){'game_exit_failure'}else{'both_processes_exited_zero'}
 }
 if($owned -and (Test-Path $proxy) -and (Get-FileHash $proxy).Hash -eq (Get-FileHash $loader).Hash){Remove-Item -LiteralPath $proxy;if($record){$record.proxy_removed=$true}}
 Close-CoopArchiveGuard $guard
 if($record){$record.ended_utc=[DateTime]::UtcNow.ToString('o');Save-Record}
}
