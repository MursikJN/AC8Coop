# Read-only kit/lab checks. Dot-sourcing does not start a process or write files.
if(!(Get-Command Get-FileHash -ErrorAction SilentlyContinue)){Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Utility/Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop}
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
 if($m.revision -ne 'r31-development' -or $m.protocol -ne 8 -or $m.pilot_protocol -ne 3 -or !$m.owner_native -or !$m.isolated_lab_required -or !$m.automatic_reports -or $m.owner_world_readiness -ne 1 -or $m.kit_update -ne 'object-readiness-1'){throw 'R31 manifest policy mismatch (object-readiness-1 required)'}
 $seen=@{};foreach($f in $m.files){
  if(!$f.path -or [IO.Path]::IsPathRooted($f.path) -or $f.path -match '(^|[\\/])\.\.([\\/]|$)' -or $f.path.Contains(':')){throw 'Invalid manifest path'}
  $path=[IO.Path]::GetFullPath((Join-Path $rootPath $f.path));if(!$path.StartsWith($rootPath+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or $seen.ContainsKey($f.path)){throw 'Duplicate or outside manifest path'}
  $seen[$f.path]=$true;Assert-CoopPlainPath $path
  if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $f.sha256){throw ('Package file mismatch: '+$f.path)}
 }
 foreach($f in @('Start-Host.cmd','Start-Guest.cmd','Prepare-Lab.cmd','Validate-Kit.cmd','Start-SteamLobby.ps1','Coop-Kit.ps1','Prepare-CoopLab.ps1','Auto-Reports.ps1','Session-Diagnostics.ps1','Collect-CoopLogs.ps1','runtime/ac8_steam_coop_r31.dll','runtime/Mods/AC8CoopRecon/Scripts/main.lua','runtime/Mods/AC8CoopRecon/Scripts/guest_owner_preparation.lua','runtime/Mods/AC8CoopRecon/Scripts/owner_local_lab.lua','Owner-Lab-Peer.exe')){if(!$seen.ContainsKey($f)){throw ('Required manifest entry missing: '+$f)}}
 $exports=@(Get-CoopPeExports (Join-Path $rootPath $m.native_file))
 foreach($e in @('luaopen_ac8_pilot_prepare','luaopen_ac8_pilot_start','luaopen_ac8_pilot_tick','luaopen_ac8_pilot_stop','luaopen_ac8_pilot_loaded','luaopen_ac8_pilot_capture_input','luaopen_ac8_lobby24_start','luaopen_ac8_invites25_open')){if($e -notin $exports){throw ('Native export missing: '+$e)}}
 return $m
}
function Test-CoopLab {
 param([string]$Root,$Manifest,[string]$GameDirectory)
 $lab=Join-Path ([IO.Path]::GetFullPath($Root)) 'lab-game'
 $expected=[IO.Path]::GetFullPath((Join-Path $lab 'Game/Binaries/Win64'))
 if($GameDirectory -and [IO.Path]::GetFullPath($GameDirectory).TrimEnd([char[]]@('\','/')) -ne $expected){throw 'R31 only launches this kit lab-game copy. Run Prepare-Lab.cmd.'}
 Assert-CoopPlainPath $expected
 $marker=Get-Content -LiteralPath (Join-Path $lab '.ac8-coop-lab.json') -Raw|ConvertFrom-Json
 if($marker.format -ne 'ac8-isolated-lab-v1' -or $marker.state -ne 'complete' -or [IO.Path]::GetFullPath($marker.destination) -ne [IO.Path]::GetFullPath($lab) -or !$marker.source -or [IO.Path]::GetFullPath($marker.source) -eq [IO.Path]::GetFullPath($lab)){throw 'Unverified laboratory copy'}
 $game=Join-Path $expected 'AceCombat8.exe';$steam=Join-Path $lab 'Engine/Binaries/ThirdParty/Steamworks/Steamv157/Win64/steam_api64.dll'
 foreach($p in @($game,$steam)){Assert-CoopPlainPath $p}
 if((Get-FileHash -LiteralPath $game).Hash -ne $Manifest.game_sha256 -or (Get-FileHash -LiteralPath $steam).Hash -ne $Manifest.steam_sha256){throw 'Laboratory game/Steam build mismatch'}
 if($marker.game_sha256 -ne $Manifest.game_sha256){throw 'Lab marker build mismatch'}
 foreach($name in @('dinput8.dll','dxgi.dll','winmm.dll','UE4SS.dll')){if(Test-Path -LiteralPath (Join-Path $expected $name)){throw ('Conflicting loader in lab: '+$name)}}
 return $expected
}
