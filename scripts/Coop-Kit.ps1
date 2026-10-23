# Read-only kit/lab checks. Dot-sourcing does not start a process or write files.
if(!(Get-Command Get-FileHash -ErrorAction SilentlyContinue)){Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Utility/Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop}
. (Join-Path $PSScriptRoot 'Coop-LabStorage.ps1')
function Assert-CoopPlainPath {
 param([string]$Path)
 $p=[IO.Path]::GetFullPath($Path)
 while($p){if(Test-Path -LiteralPath $p){if((Get-Item -LiteralPath $p -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw ('Linked path is not permitted: '+$p)}};$parent=Split-Path $p -Parent;if($parent -eq $p){break};$p=$parent}
}
function Get-CoopPeExports {
 param([string]$Path)
 $b=[IO.File]::ReadAllBytes($Path)
 if($b.Length -lt 512 -or [BitConverter]::ToUInt16($b,0) -ne 0x5a4d){throw 'Not a PE image'}
 $pe=[BitConverter]::ToInt32($b,60);if($pe -lt 64 -or $pe+264 -gt $b.Length -or [BitConverter]::ToUInt32($b,$pe) -ne 0x4550 -or [BitConverter]::ToUInt16($b,$pe+4) -ne 0x8664 -or [BitConverter]::ToUInt16($b,$pe+24) -ne 0x20b){throw 'Not an x64 PE image'}
 $count=[BitConverter]::ToUInt16($b,$pe+6);$start=$pe+24+[BitConverter]::ToUInt16($b,$pe+20)
 $map={param([uint32]$Rva)for($i=0;$i -lt $count;$i++){$s=$start+$i*40;$va=[BitConverter]::ToUInt32($b,$s+12);$size=[BitConverter]::ToUInt32($b,$s+16);if($Rva -ge $va -and $Rva-$va -lt $size){return [int]([BitConverter]::ToUInt32($b,$s+20)+$Rva-$va)}};throw 'PE RVA outside file sections'}
 $rva=[BitConverter]::ToUInt32($b,$pe+24+112);if(!$rva){return @()};$exp=& $map $rva
 $n=[BitConverter]::ToUInt32($b,$exp+24);if($n -gt 65536){throw 'PE export budget'};$names=& $map ([BitConverter]::ToUInt32($b,$exp+32))
 for($i=0;$i -lt $n;$i++){$at=& $map ([BitConverter]::ToUInt32($b,$names+4*$i));$end=$at;while($end -lt $b.Length -and $end-$at -lt 256 -and $b[$end]){$end++};if($end -ge $b.Length -or $end-$at -ge 256){throw 'Invalid export name'};[Text.Encoding]::ASCII.GetString($b,$at,$end-$at)}
}
function Test-CoopKit {
 param([string]$Root)
 $rootPath=[IO.Path]::GetFullPath($Root).TrimEnd([char[]]@('\','/'));Assert-CoopPlainPath $rootPath
 $m=Get-Content -LiteralPath (Join-Path $rootPath 'lobby-manifest.json') -Raw|ConvertFrom-Json
 if($m.revision -ne 'r31-development' -or $m.protocol -ne 8 -or $m.pilot_protocol -ne 3 -or !$m.owner_native -or !$m.isolated_lab_required -or !$m.automatic_reports -or $m.owner_world_readiness -ne 1 -or $m.kit_update -notin @('cinema-2','local-stage1') -or $m.cinema_metadata -ne 1 -or $m.native_shutdown -ne 1 -or $m.menu_lifetime -ne 1 -or $m.engine_call_trace -ne 1 -or $m.adapter_bootstrap -ne 1 -or $m.lab_storage_policy -ne 3){throw 'R31 manifest policy mismatch (cinema-2 or local-stage1 required)'}
 $seen=@{};foreach($f in $m.files){
  if(!$f.path -or [IO.Path]::IsPathRooted($f.path) -or $f.path -match '(^|[\\/])\.\.([\\/]|$)' -or $f.path.Contains(':')){throw 'Invalid manifest path'}
  $path=[IO.Path]::GetFullPath((Join-Path $rootPath $f.path));if(!$path.StartsWith($rootPath+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or $seen.ContainsKey($f.path)){throw 'Duplicate or outside manifest path'}
  $seen[$f.path]=$true;Assert-CoopPlainPath $path
  if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $f.sha256){throw ('Package file mismatch: '+$f.path)}
 }
 foreach($f in @('Start-Host.cmd','Start-Guest.cmd','Prepare-Lab.cmd','Validate-Kit.cmd','Start-SteamLobby.ps1','Coop-Kit.ps1','Coop-LabStorage.ps1','Prepare-CoopLab.ps1','Auto-Reports.ps1','Session-Diagnostics.ps1','Collect-CoopLogs.ps1','runtime/ac8_steam_coop_r31.dll','runtime/Mods/AC8CoopRecon/Scripts/main.lua','runtime/Mods/AC8CoopRecon/Scripts/guest_owner_preparation.lua','runtime/Mods/AC8CoopRecon/Scripts/owner_local_lab.lua','Owner-Lab-Peer.exe')){if(!$seen.ContainsKey($f)){throw ('Required manifest entry missing: '+$f)}}
 $exports=@(Get-CoopPeExports (Join-Path $rootPath $m.native_file))
 if($m.kit_update -eq 'local-stage1'){
  if($m.local_model_stage -ne 1 -or $m.owner_sound_readiness -ne 1){throw 'Local stage 1 policy mismatch'}
  if($m.local_model_patch -eq 'cleanup-1' -and ($m.owner_tick_cleanup -ne 1 -or $m.owner_cleanup_gc_gate -ne 1)){throw 'Local tick teardown/GC gate support missing'}
  foreach($f in @('Start-LocalModelTest.cmd','LOCAL-MODEL-TEST-RU.md')){if(!$seen.ContainsKey($f)){throw ('Local test entry missing: '+$f)}}
  foreach($e in @('luaopen_ac8_pilot_preflight','luaopen_ac8_pilot_clock')){if($e -notin $exports){throw ('Local test export missing: '+$e)}}
  if($m.local_model_patch -in @('start-1','cdo-1','lifetime-1','cleanup-1') -and ($m.owner_camera_receipt -ne 1 -or 'luaopen_ac8_pilot_track_camera' -notin $exports)){throw 'Local camera retirement receipt support missing'}
  if($m.local_model_patch -in @('cdo-1','lifetime-1','cleanup-1') -and ($m.owner_template_identity -ne 1 -or $m.helper_preparation_timeout_ms -ne 60000)){throw 'Local template identity/loading window policy missing'}
  if($m.local_model_patch -in @('lifetime-1','cleanup-1') -and ($m.owner_template_retention -ne 1 -or $m.owner_dependency_identity -ne 1 -or 'luaopen_ac8_pilot_retain_template' -notin $exports)){throw 'Local template retention/dependency identity support missing'}
 }
 foreach($f in @('Repair-Lab.cmd','Repair-CompactLab.ps1','runtime/Mods/AC8CoopRecon/Scripts/lobby_menu_lifetime.lua','runtime/Mods/AC8CoopRecon/Scripts/engine_call_trace.lua')){if(!$seen.ContainsKey($f)){throw ('Required manifest entry missing: '+$f)}}
 foreach($e in @('luaopen_ac8_shutdown_begin','luaopen_ac8_shutdown_poll','luaopen_ac8_pilot_prepare','luaopen_ac8_pilot_start','luaopen_ac8_pilot_tick','luaopen_ac8_pilot_stop','luaopen_ac8_pilot_loaded','luaopen_ac8_pilot_capture_input','luaopen_ac8_lobby24_start','luaopen_ac8_invites25_open')){if($e -notin $exports){throw ('Native export missing: '+$e)}}
 foreach($entry in @(@('runtime/ac8_menu_route_r13.dll','luaopen_ac8_menu_route'),@('runtime/ac8_mission_pause_r26.dll','luaopen_ac8_mission_pause'))){if($entry[0] -notin $seen.Keys -or $entry[1] -notin @(Get-CoopPeExports (Join-Path $rootPath $entry[0]))){throw ('Required adapter export missing: '+$entry[0])}}
 if(!$seen.ContainsKey('Coop-AdapterEnvironment.ps1')){throw 'Adapter environment helper missing'}
 return $m
}
function Test-CoopLab {
 param([string]$Root,$Manifest,[string]$GameDirectory,[ref]$ArchiveGuard)
 $lab=Join-Path ([IO.Path]::GetFullPath($Root)) 'lab-game'
 $expected=[IO.Path]::GetFullPath((Join-Path $lab 'Game/Binaries/Win64'))
 if($GameDirectory -and [IO.Path]::GetFullPath($GameDirectory).TrimEnd([char[]]@('\','/')) -ne $expected){throw 'R31 only launches this kit lab-game copy. Run Prepare-Lab.cmd.'}
 Assert-CoopPlainPath $expected
 $markerPath=Join-Path $lab '.ac8-coop-lab.json'
 if(!(Test-Path -LiteralPath $markerPath)){throw 'Lab is not prepared. Run Prepare-Lab.cmd, choose the original ACE COMBAT 8 folder, then Validate-Lab.cmd. Compact mode needs about 5 GB plus reserve.'}
 Assert-CoopPlainPath $markerPath
 $marker=Get-Content -LiteralPath $markerPath -Raw|ConvertFrom-Json
 if($marker.format -eq 'ac8-isolated-lab-v2' -and $marker.storage_mode -eq 'compact'){throw 'Old compact-1 file-link layout. Run Repair-Lab.cmd from the updated kit; no game files need recopying.'}
 if($marker.format -ne 'ac8-isolated-lab-v3' -or $marker.state -ne 'complete' -or $marker.storage_mode -notin @('compact','full') -or ($marker.storage_mode -eq 'compact' -and $marker.archive_layout -ne 'paks-junction-v1') -or [IO.Path]::GetFullPath($marker.destination) -ne [IO.Path]::GetFullPath($lab) -or !$marker.source -or [IO.Path]::GetFullPath($marker.source) -eq [IO.Path]::GetFullPath($lab)){throw 'Unverified laboratory copy; preserve it and prepare a fresh compact kit.'}
 $source=[IO.Path]::GetFullPath($marker.source).TrimEnd([char[]]@('\','/'))
 if($source.StartsWith($lab+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or $lab.StartsWith($source+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Source and lab trees overlap'}
 Assert-CoopPlainPath $source
 Assert-CoopLabTree -Root $Root -Marker $marker
 $game=Join-Path $expected 'AceCombat8.exe';$steam=Join-Path $lab 'Engine/Binaries/ThirdParty/Steamworks/Steamv157/Win64/steam_api64.dll'
 foreach($p in @($game,$steam)){Assert-CoopPlainPath $p}
 if((Get-FileHash -LiteralPath $game).Hash -ne $Manifest.game_sha256 -or (Get-FileHash -LiteralPath $steam).Hash -ne $Manifest.steam_sha256){throw 'Laboratory game/Steam build mismatch'}
 if($marker.game_sha256 -ne $Manifest.game_sha256){throw 'Lab marker build mismatch'}
 if((Get-FileHash -LiteralPath (Join-Path $source 'Game/Binaries/Win64/AceCombat8.exe')).Hash -ne $Manifest.game_sha256){throw 'Original game build changed; prepare a fresh supported kit after Steam updates.'}
 Assert-CoopSeparateBinary -Copy $game -Original (Join-Path $source 'Game/Binaries/Win64/AceCombat8.exe')
 Assert-CoopSeparateBinary -Copy $steam -Original (Join-Path $source 'Engine/Binaries/ThirdParty/Steamworks/Steamv157/Win64/steam_api64.dll')
 foreach($name in @('dinput8.dll','dxgi.dll','winmm.dll','UE4SS.dll')){if(Test-Path -LiteralPath (Join-Path $expected $name)){throw ('Conflicting loader in lab: '+$name)}}
 $held=$null
 try{
  if($marker.storage_mode -eq 'compact'){$held=Open-CoopArchiveGuard -Root $Root -Marker $marker}
  if($ArchiveGuard){$ArchiveGuard.Value=$held;$held=$null}
  return $expected
 }finally{Close-CoopArchiveGuard $held}
}
