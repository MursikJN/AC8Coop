[CmdletBinding()]
param([string]$ProfileRoot,[switch]$Launch,[switch]$SteamOfflineConfirmed,[switch]$AutomationBridge,[switch]$BaxterStudy)
$ErrorActionPreference='Stop'
if(!$ProfileRoot){$ProfileRoot=$PSScriptRoot}
$ProfileRoot=[IO.Path]::GetFullPath($ProfileRoot)
. (Join-Path $ProfileRoot 'Coop-Kit.ps1')
Assert-CoopPlainPath $ProfileRoot
$cfg=Get-Content -LiteralPath (Join-Path $ProfileRoot 'capture-profile.json') -Raw|ConvertFrom-Json
if($cfg.format -ne 'ac8-mission6-capture-v1' -or $cfg.game_sha256 -ne '51510e2a520565dbe81fb0d569e95cd4393077acaaa859371489b80b8128829f'){throw 'Unsupported capture profile'}
$seen=@{}
$queue=New-Object 'System.Collections.Generic.Queue[string]';$queue.Enqueue((Join-Path $ProfileRoot 'runtime'))
while($queue.Count){foreach($item in Get-ChildItem -LiteralPath $queue.Dequeue() -Force){if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Linked runtime entry refused'};if($item.PSIsContainer){$queue.Enqueue($item.FullName)}}}
foreach($f in $cfg.files){
 if([IO.Path]::IsPathRooted($f.path) -or $f.path -match '(^|[\\/])\.\.([\\/]|$)|:' -or $seen.ContainsKey($f.path)){throw 'Invalid profile manifest path'}
 $seen[$f.path]=$true;$p=Join-Path $ProfileRoot $f.path;Assert-CoopPlainPath $p
 if((Get-FileHash -LiteralPath $p).Hash -ne $f.sha256){throw ('Profile changed: '+$f.path)}
}
foreach($required in @('runtime/UE4SS.dll','runtime/UE4SS-settings.ini','runtime/Mods/mods.txt','runtime/Mods/Mission6Capture/Scripts/main.lua','runtime/Mods/Mission6Capture/Scripts/capture.lua','loader/dwmapi.dll','Start-Mission6Capture.ps1','Coop-Kit.ps1','Coop-LabStorage.ps1')){if(!$seen.ContainsKey($required)){throw ('Missing capture manifest entry: '+$required)}}
foreach($f in Get-ChildItem -LiteralPath (Join-Path $ProfileRoot 'runtime') -Recurse -File){
 $rel=$f.FullName.Substring($ProfileRoot.Length+1).Replace('\','/');if(!$seen.ContainsKey($rel)){throw ('Unexpected runtime file: '+$rel)}
}
$private=[IO.Path]::GetFullPath($cfg.private_root);Assert-CoopPlainPath $private
$marker=Get-Content -LiteralPath (Join-Path $cfg.kit_root 'lab-game/.ac8-coop-lab.json') -Raw|ConvertFrom-Json
foreach($forbidden in @($marker.source,$marker.destination,$ProfileRoot)){
 $base=[IO.Path]::GetFullPath($forbidden).TrimEnd('\','/')
 if($private -eq $base -or $private.StartsWith($base+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Private output overlaps protected tree'}
}
$guard=$null;$owned=$false;$process=$null;$record=$null;$session=$null
try{
 $gameDir=Test-CoopLab -Root $cfg.kit_root -Manifest $cfg -ArchiveGuard ([ref]$guard)
 $proxy=Join-Path $gameDir 'dwmapi.dll';if(Test-Path -LiteralPath $proxy){throw 'Existing loader belongs to another launcher; no cleanup attempted'}
 if(!$Launch){Write-Output 'Capture preflight PASS; no launch, no game writes.';return}
 if(Get-Process AceCombat8,start_protected_game,EasyAntiCheat_EOS -ErrorAction SilentlyContinue){throw 'Close game and protected launcher normally first'}
 if(!$SteamOfflineConfirmed){
  Write-Host 'Put Steam in Offline Mode first. This observer never creates or joins a network session.'
  if((Read-Host 'Type OFFLINE to confirm, or press Enter to cancel') -cne 'OFFLINE'){throw 'Offline mode not confirmed; not launched'}
 }
 $session=Join-Path $private ('session-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
 New-Item -ItemType Directory -Path $session|Out-Null
 Copy-Item -LiteralPath (Join-Path $ProfileRoot 'runtime') -Destination (Join-Path $session 'runtime') -Recurse
 Copy-Item -LiteralPath (Join-Path $ProfileRoot 'capture-profile.json') -Destination $session
 $user=Join-Path $session 'userdata';$saved=Join-Path $user 'Saved';New-Item -ItemType Directory -Path $saved|Out-Null
 # Read a one-time copy of existing progress; never sync research saves back.
 $originalSaved=Join-Path $env:LOCALAPPDATA 'BANDAI NAMCO Entertainment/ACE COMBAT 8/Saved'
 foreach($name in @('SaveGames','Config')){
  $src=Join-Path $originalSaved $name
  if(Test-Path -LiteralPath $src){
   Assert-CoopPlainPath $src
   $queue=New-Object 'System.Collections.Generic.Queue[string]';$queue.Enqueue($src)
   while($queue.Count){foreach($item in Get-ChildItem -LiteralPath $queue.Dequeue() -Force){if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Linked save/config source refused'};if($item.PSIsContainer){$queue.Enqueue($item.FullName)}}}
   Copy-Item -LiteralPath $src -Destination (Join-Path $saved $name) -Recurse
  }
 }
 $output=Join-Path $session 'observations';New-Item -ItemType Directory -Path $output|Out-Null
 $info=New-Object Diagnostics.ProcessStartInfo
 $info.FileName=Join-Path $gameDir 'AceCombat8.exe';$info.WorkingDirectory=$gameDir;$info.UseShellExecute=$false
 $runtime=Join-Path $session 'runtime/UE4SS.dll'
 $info.Arguments='-SaveToUserDir -UserDir="'+$user+'" -windowed -ResX=1280 -ResY=720 --ue4ss-path "'+$runtime+'"'
 foreach($key in @($info.EnvironmentVariables.Keys)){if($key -like 'AC8_*'){$info.EnvironmentVariables.Remove($key)}}
 $info.EnvironmentVariables['SteamAppId']='2288340'
 $info.EnvironmentVariables['AC8_MISSION6_CAPTURE']='25201480'
 $info.EnvironmentVariables['AC8_MISSION6_OUTPUT']=$output
 $info.EnvironmentVariables['AC8_MISSION6_SCRIPTS']=Join-Path $session 'runtime/Mods/Mission6Capture/Scripts'
 if($BaxterStudy){
  if(!$seen.ContainsKey('runtime/Mods/Mission6Capture/Scripts/baxter.lua')){throw 'Baxter study missing from manifest'}
  $info.EnvironmentVariables['AC8_BAXTER_STUDY']='1'
 }
 if($AutomationBridge){
  if(!$seen.ContainsKey('runtime/Mods/Mission6Capture/Scripts/automation.lua')){throw 'Automation bridge missing from manifest'}
  $info.EnvironmentVariables['AC8_CAPTURE_AUTOMATION']='1'
 }
 $record=[ordered]@{format='ac8-mission6-observation-v1';started_utc=[DateTime]::UtcNow.ToString('o');game=$info.FileName;game_sha256=$cfg.game_sha256;userdata=$user;pid=$null;exit_code=$null;offline_user_confirmed=$true;network_isolation_os_verified=$false;originals_written=$false;proxy_removed=$false;error=$null}
 $record|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $session 'session.json') -Encoding UTF8
 [IO.File]::Copy((Join-Path $ProfileRoot 'loader/dwmapi.dll'),$proxy,$false);$owned=$true
 $process=[Diagnostics.Process]::Start($info);$record.pid=$process.Id
 $record|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $session 'session.json') -Encoding UTF8
 Write-Output ('Observer output: '+$output)
 $process.WaitForExit();$record.exit_code=$process.ExitCode
}catch{if($record){$record.error=$_.Exception.Message};throw
}finally{
 # Keep archive read locks and loader ownership until this process exits normally.
 if($process -and !$process.HasExited){$process.WaitForExit()}
 if($owned -and (Test-Path -LiteralPath $proxy)){
  if((Get-FileHash -LiteralPath $proxy).Hash -eq (Get-FileHash -LiteralPath (Join-Path $ProfileRoot 'loader/dwmapi.dll')).Hash){Remove-Item -LiteralPath $proxy;if($record){$record.proxy_removed=$true}}
 }
 Close-CoopArchiveGuard $guard
 if($record){
  $record.ended_utc=[DateTime]::UtcNow.ToString('o');$record|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $session 'session.json') -Encoding UTF8
  Get-ChildItem -LiteralPath (Join-Path $session 'observations') -File|ForEach-Object {[ordered]@{path=$_.Name;bytes=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}}|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $session 'observations-manifest.json') -Encoding UTF8
 }
}
